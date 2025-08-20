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

/// Главное содержимое окна из строки меню
struct MenuContent: View {
    @ObservedObject var battery: BatteryViewModel
    @ObservedObject var history: HistoryStore
    @ObservedObject var analytics: AnalyticsEngine
    @ObservedObject var calibrator: CalibrationEngine
    @ObservedObject var loadGenerator: LoadGenerator
    // Video load removed
    @ObservedObject var safetyGuard: LoadSafetyGuard
    @ObservedObject var updateChecker: UpdateChecker
    @ObservedObject var i18n: Localization = .shared
    @Environment(\.colorScheme) var colorScheme
    @State private var isAnalyzing = false
    @State private var panel: Panel
    @State private var hasNotch = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var isWindowVisible = true
    
    // Опционально принимаем windowState для синхронизации
    private let windowState: WindowState?
    @ObservedObject var quickHealthTest: QuickHealthTest
    @ObservedObject var alertManager: AlertManager = AlertManager.shared
    
    /// Инициализатор с возможностью задать начальную панель
    init(
        battery: BatteryViewModel,
        history: HistoryStore,
        analytics: AnalyticsEngine,
        calibrator: CalibrationEngine,
        loadGenerator: LoadGenerator,
        safetyGuard: LoadSafetyGuard,
        updateChecker: UpdateChecker,
        initialPanel: Panel = .overview,
        windowState: WindowState? = nil,
        quickHealthTest: QuickHealthTest
    ) {
        self.battery = battery
        self.history = history
        self.analytics = analytics
        self.calibrator = calibrator
        self.loadGenerator = loadGenerator
        self.safetyGuard = safetyGuard
        self.updateChecker = updateChecker
        self.windowState = windowState
        self.quickHealthTest = quickHealthTest
        self._panel = State(initialValue: initialPanel)
    }
    
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
                            windowState?.switchToPanel(p)
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
                // Открыть вкладку настроек
                Button {
                    panel = .settings
                } label: {
                    Image(systemName: "gearshape")
                }
                .help(i18n.t("settings"))
                // Открыть вкладку About
                Button {
                    panel = .about
                } label: {
                    Image(systemName: "info.circle")
                }
                .help(i18n.t("about"))
            }

            Divider()

            ScrollView {
                Group {
                    switch panel {
                    case .overview: overview
                    case .trends: ChartsPanel(history: history, calibrator: calibrator, snapshot: battery.state)
                    case .test: CalibrationPanel(
                        battery: battery,
                        calibrator: calibrator, 
                        history: history,
                        analytics: analytics, 
                        snapshot: battery.state,
                        loadGenerator: loadGenerator,
                        safetyGuard: safetyGuard,
                        quickHealthTest: quickHealthTest
                    )
                    case .settings: SettingsPanel(history: history, calibrator: calibrator)
                    case .about: AboutPanel(updateChecker: updateChecker)
                    }
                }
            }

        }
        .padding(10)
        .frame(minWidth: 650, minHeight: 480)
        .safeAreaPadding(.top, topPadding)
        .animation(.default, value: battery.state)
        .onAppear {
            // Проверяем наличие челки на текущем экране для корректного позиционирования окна
            // На MacBook'ах с челкой (M2+) окно может провалиться под челку при скрытом меню-баре
            hasNotch = NSScreen.main?.hasNotch ?? false
            
            // Синхронизируем активную панель из windowState при первом появлении
            if let windowState = windowState, panel != windowState.activePanel {
                panel = windowState.activePanel
            }
            
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
                windowState?.switchToPanel(.settings)
            } label: {
                Label(i18n.t("settings"), systemImage: "gearshape")
            }
            
            Button {
                panel = .about
                windowState?.switchToPanel(.about)
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
        .onChange(of: windowState?.activePanel) { _, newPanel in
            if let newPanel = newPanel, newPanel != panel {
                panel = newPanel
            }
        }
        .withAlerts()
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
                        HStack(spacing: 4) {
                            Text(getPowerSourceText())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(i18n.t("power.battery"))
                            // Текущая мощность потребления
                            if abs(battery.state.power) > 0.1 {
                                HStack(spacing: 2) {
                                    Image(systemName: battery.state.power < 0 ? "bolt.fill" : "arrow.up.circle.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(battery.state.power < 0 ? .red : .green)
                                    Text(String(format: "%.1f W", abs(battery.state.power)))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .help(battery.state.power < 0 ? i18n.t("tooltip.power.discharging") : i18n.t("tooltip.power.charging"))
                            }
                        }
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
                if loadGenerator.isRunning {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                            .animation(isWindowVisible ? .easeInOut(duration: 1).repeatForever(autoreverses: true) : .none, value: loadGenerator.isRunning)
                        Text(i18n.t("cpu.label"))
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
    
    /// Новая метрика вместо "%/час": тренд энергопотребления
    private func getPowerConsumptionTrend() -> String {
        let currentPower = analytics.getAveragePowerLast15Min(history: history.items)
        let analysis = analytics.lastAnalysis
        
        guard currentPower > 0.1 else { 
            return i18n.t("collecting.stats")
        }
        
        if i18n.language == .ru {
            if let avgPower = analysis?.averagePower, avgPower > 0 {
                let change = ((currentPower - avgPower) / avgPower) * 100
                if abs(change) < 5 {
                    return String(format: "%.1f Вт • стабильно", currentPower)
                } else if change > 0 {
                    return String(format: "%.1f Вт • ↑%.0f%%", currentPower, change)
                } else {
                    return String(format: "%.1f Вт • ↓%.0f%%", currentPower, abs(change))
                }
            }
            return String(format: "%.1f Вт", currentPower)
        } else {
            if let avgPower = analysis?.averagePower, avgPower > 0 {
                let change = ((currentPower - avgPower) / avgPower) * 100
                if abs(change) < 5 {
                    return String(format: "%.1f W • stable", currentPower)
                } else if change > 0 {
                    return String(format: "%.1f W • ↑%.0f%%", currentPower, change)
                } else {
                    return String(format: "%.1f W • ↓%.0f%%", currentPower, abs(change))
                }
            }
            return String(format: "%.1f W", currentPower)
        }
    }
    
    /// Новая метрика: эффективность использования энергии батареи
    private func getEnergyEfficiency() -> String {
        guard let analysis = analytics.lastAnalysis else {
            return i18n.t("collecting.stats")
        }
        
        let sohEnergy = analysis.sohEnergy
        let sohCapacity = 100 - battery.state.wearPercent
        
        if sohEnergy <= 0 || sohCapacity <= 0 {
            return i18n.t("collecting.stats")
        }
        
        // Ограничиваем эффективность максимумом 100%
        let efficiency = min((sohEnergy / sohCapacity) * 100, 100)
        
        return String(format: "%.0f%%", efficiency)
    }
    
    /// Цвет для метрики эффективности энергии
    private func getEnergyEfficiencyColor() -> Color {
        guard let analysis = analytics.lastAnalysis else { return .secondary }
        
        let sohEnergy = analysis.sohEnergy
        let sohCapacity = 100 - battery.state.wearPercent
        
        if sohEnergy <= 0 || sohCapacity <= 0 {
            return .secondary
        }
        
        // Ограничиваем эффективность максимумом 100%
        let efficiency = min((sohEnergy / sohCapacity) * 100, 100)
        
        if efficiency >= 95 {
            return .green
        } else if efficiency >= 85 {
            return .orange
        } else {
            return .red
        }
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
    
    // MARK: - Health Score функции
    
    private func getHealthScore() -> Int {
        return analytics.getHealthScore(history: history.items, snapshot: battery.state)
    }
    
    private func getHealthStatus() -> HealthStatus {
        return analytics.getHealthStatusFromScore(getHealthScore())
    }
    
    /// Возвращает текст для отображения вместо Health Score во время сбора данных
    private func getHealthScoreDisplayValue() -> String {
        if !analytics.isDataCollectionComplete() {
            let remainingTime = analytics.getRemainingDataCollectionTime()
            if remainingTime > 0 {
                return String(format: i18n.t("health.score.time.remaining"), remainingTime)
            } else {
                return i18n.t("health.score.collecting")
            }
        } else {
            return "\(getHealthScore())/100"
        }
    }
    
    /// Проверяет, идет ли сбор данных для Health Score
    private func isHealthScoreCollecting() -> Bool {
        return !analytics.isDataCollectionComplete()
    }
    
    private func getHealthConditionText() -> String {
        let status = getHealthStatus()
        switch status {
        case .excellent: return i18n.language == .ru ? "Отличное" : "Excellent"
        case .normal: return i18n.language == .ru ? "Хорошее" : "Good"
        case .acceptable: return i18n.language == .ru ? "Приемлемое" : "Fair"
        case .poor: return i18n.language == .ru ? "Требует внимания" : "Needs Attention"
        case .afterTest: return i18n.language == .ru ? "После теста" : "After Test"
        }
    }
    
    private func getAveragePower15Min() -> String {
        let power = analytics.getAveragePowerLast15Min(history: history.items)
        guard power > 0.1 else { return i18n.t("collecting.stats") }
        return String(format: "%.1f W", power)
    }
    
    private func getRuntimeForPowerPreset(_ power: Double) -> String {
        let designCapacity = Double(battery.state.designCapacity)
        let maxCapacity = Double(battery.state.maxCapacity)
        guard designCapacity > 0, maxCapacity > 0, power > 0 else { return "—" }
        
        // Приблизительная энергия батареи в Вт·ч (используем номинальное напряжение ~11.4В)
        let batteryEnergyWh = maxCapacity * 11.4 / 1000.0
        let runtimeHours = batteryEnergyWh / power
        
        if runtimeHours >= 1.0 {
            return String(format: "%.1fч", runtimeHours)
        } else {
            return String(format: "%.0fм", runtimeHours * 60)
        }
    }

    /// Время работы для эквивалентного C‑рейта (0.1C/0.2C/0.3C) по рекомендациям эксперта
    private func getRuntimeForCRate(_ cRate: Double) -> String {
        let designMah = battery.state.designCapacity
        guard designMah > 0, cRate > 0 else { return "—" }
        // Используем среднее V_OC, если доступно в аналитике; иначе номинал 11.1В
        let avgVOC = OCVAnalyzer.averageVOC(from: history.items) ?? 11.1
        let designWh = Double(designMah) * max(5.0, avgVOC) / 1000.0
        let sohCap = battery.state.maxCapacity > 0 ? Double(battery.state.maxCapacity) / Double(designMah) : 1.0
        let effectiveWh = max(0.0, min(1.0, sohCap)) * designWh
        let targetW = designWh * cRate
        guard targetW > 0 else { return "—" }
        let hours = effectiveWh / targetW
        if hours >= 1.0 { return String(format: "%.1fч", hours) }
        return String(format: "%.0fм", hours * 60)
    }
    
    /// Получить текст для пресета мощности с указанием ватт
    private func getPowerPresetText(_ cRate: Double) -> String {
        let designMah = battery.state.designCapacity
        guard designMah > 0, cRate > 0 else {
            if i18n.language == .ru {
                return cRate == 0.1 ? "Лёгкая" : cRate == 0.2 ? "Средняя" : "Тяжёлая"
            } else {
                return cRate == 0.1 ? "Light" : cRate == 0.2 ? "Medium" : "Heavy"
            }
        }
        
        let avgVOC = OCVAnalyzer.averageVOC(from: history.items) ?? 11.1
        let designWh = Double(designMah) * max(5.0, avgVOC) / 1000.0
        let targetW = designWh * cRate
        
        if i18n.language == .ru {
            return String(format: "%.0f Вт", targetW)
        } else {
            return String(format: "%.0f W", targetW)
        }
    }
    
    // MARK: - Новые функции для метрик согласно рекомендациям профессора
    
    private func getSOHEnergy() -> String {
        // Получаем SOH по энергии из последнего анализа
        if let analysis = analytics.lastAnalysis {
            if analysis.sohEnergy > 0 {
                return String(format: "%.1f%%", analysis.sohEnergy)
            }
        }
        return i18n.t("collecting.stats")
    }
    
    private func getDCIRValue() -> String {
        // Получаем DCIR статус вместо числового значения
        if let analysis = analytics.lastAnalysis,
           let dcir50 = analysis.dcirAt50Percent, dcir50 > 0 {
            // Оценка DCIR согласно рекомендациям профессора
            if dcir50 <= 120 {
                return i18n.t("dcir.status.excellent")
            } else if dcir50 <= 200 {
                return i18n.t("dcir.status.good")
            } else if dcir50 <= 300 {
                return i18n.t("dcir.status.warning")
            } else {
                return i18n.t("dcir.status.poor")
            }
        }
        return i18n.t("collecting.stats")
    }
    
    private func getDCIRHealthStatus() -> HealthStatus? {
        guard let analysis = analytics.lastAnalysis,
              let dcir50 = analysis.dcirAt50Percent, dcir50 > 0 else { return nil }
        
        // Оценка DCIR согласно рекомендациям профессора
        if dcir50 <= 120 {
            return HealthStatus.excellent
        } else if dcir50 <= 200 {
            return HealthStatus.normal
        } else if dcir50 <= 300 {
            return HealthStatus.acceptable
        } else {
            return HealthStatus.poor
        }
    }
    
    private func getMicroDrops() -> String {
        if let analysis = analytics.lastAnalysis {
            let microDrops = analysis.microDropEvents
            // Отображаем статус вместо числа
            if microDrops == 0 {
                return i18n.t("micro.drops.status.excellent")
            } else if microDrops <= 2 {
                return i18n.t("micro.drops.status.good")
            } else if microDrops <= 5 {
                return i18n.t("micro.drops.status.warning")
            } else {
                return i18n.t("micro.drops.status.problem")
            }
        }
        return i18n.t("micro.drops.status.excellent")
    }
    
    private func getMicroDropHealthStatus() -> HealthStatus? {
        guard let analysis = analytics.lastAnalysis else { return nil }
        
        let microDrops = analysis.microDropEvents
        
        // Простая оценка по абсолютному количеству микро-дропов
        if microDrops == 0 {
            return HealthStatus.excellent
        } else if microDrops <= 2 {
            return HealthStatus.normal
        } else if microDrops <= 5 {
            return HealthStatus.acceptable
        } else {
            return HealthStatus.poor
        }
    }
    
    private func getKneeIndex() -> String {
        if let analysis = analytics.lastAnalysis, analysis.kneeIndex > 0 {
            return String(format: "%.0f", analysis.kneeIndex)
        } else {
            return i18n.t("collecting.stats")
        }
    }
    
    private func temperatureStatus(_ temperature: Double) -> String {
        // Simple text label for user clarity: Normal / High
        if temperature > 40 {
            return i18n.t("temperature.status.high")
        } else {
            return i18n.t("temperature.status.normal")
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Основные метрики батареи и производительности - 3 колонки
            CardSection(title: i18n.t("overview.battery.info"), icon: "battery.100") {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    // Первый ряд: Health Score, Время работы, Средняя мощность
                    EnhancedStatCard(
                        title: i18n.t("health.score"),
                        value: getHealthScoreDisplayValue(),
                        icon: "heart.fill",
                        accentColor: isHealthScoreCollecting() ? .secondary : 
                                   (getHealthStatus().color == "green" ? .green : 
                                   getHealthStatus().color == "orange" ? .orange : 
                                   getHealthStatus().color == "red" ? .red : .blue),
                        healthStatus: isHealthScoreCollecting() ? nil : getHealthStatus(),
                        isCollectingData: isHealthScoreCollecting()
                    )
                    .help(isHealthScoreCollecting() ? i18n.t("health.score.collecting.hint") : "")
                    EnhancedStatCard(
                        title: i18n.t("runtime.estimated"),
                        value: estimatedRuntimeText(),
                        icon: "clock",
                        accentColor: hasAnyDischargeData() ? (getEstimatedRuntime() < 3 ? .red : Color.accentColor) : .secondary,
                        isCollectingData: isCollectingRuntime()
                    )
                    EnhancedStatCard(
                        title: i18n.t("average.power.15min"),
                        value: getAveragePower15Min(),
                        icon: "bolt.fill",
                        accentColor: analytics.getAveragePowerLast15Min(history: history.items) > 15 ? .orange : Color.accentColor,
                        isCollectingData: analytics.getAveragePowerLast15Min(history: history.items) <= 0.1
                    )
                    
                    // Второй ряд: Износ, Температура, Тренд потребления
                    EnhancedStatCard(
                        title: i18n.t("wear"),
                        value: (battery.state.designCapacity > 0 && battery.state.maxCapacity > 0)
                               ? String(format: "%.0f%%", battery.state.wearPercent)
                               : i18n.t("dash"),
                        icon: "chart.line.downtrend.xyaxis",
                        accentColor: getHealthStatus().color == "green" ? .green : 
                                   getHealthStatus().color == "orange" ? .orange : 
                                   getHealthStatus().color == "red" ? .red : .blue
                    )
                    EnhancedStatCard(
                        title: i18n.t("temperature"),
                        value: battery.state.temperature > 0 ? String(format: "%.1f°C • %@", battery.state.temperature, temperatureStatus(battery.state.temperature)) : i18n.t("dash"),
                        icon: "thermometer",
                        accentColor: battery.state.temperature > 40 ? .red : 
                                   battery.state.temperature > 35 ? .orange : Color.accentColor
                    )
                    .help(i18n.language == .ru ? "Длительно >40°C ускоряет износ" : "Prolonged >40°C accelerates wear")
                    EnhancedStatCard(
                        title: i18n.t("power.consumption.trend"),
                        value: getPowerConsumptionTrend(),
                        icon: "chart.line.uptrend.xyaxis",
                        accentColor: analytics.getAveragePowerLast15Min(history: history.items) > 20 ? .orange : Color.accentColor,
                        isCollectingData: analytics.getAveragePowerLast15Min(history: history.items) <= 0.1
                    )
                    .help(i18n.language == .ru ? "Тренд энергопотребления за последние дни" : "Power consumption trend over recent days")
                }

                // Компактный блок прогнозов времени для типовых нагрузок (пересчитанных как 0.1C/0.2C/0.3C)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                        Text(i18n.t("power.presets"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text(getPowerPresetText(0.1)).font(.caption2).foregroundStyle(.secondary)
                            Text(getRuntimeForCRate(0.1)).font(.caption2).fontWeight(.medium)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.1), in: Capsule())
                        HStack(spacing: 4) {
                            Text(getPowerPresetText(0.2)).font(.caption2).foregroundStyle(.secondary)
                            Text(getRuntimeForCRate(0.2)).font(.caption2).fontWeight(.medium)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.1), in: Capsule())
                        HStack(spacing: 4) {
                            Text(getPowerPresetText(0.3)).font(.caption2).foregroundStyle(.secondary)
                            Text(getRuntimeForCRate(0.3)).font(.caption2).fontWeight(.medium)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.red.opacity(0.1), in: Capsule())
                        Spacer()
                    }
                }
            }
            
            // Экспертные метрики (всегда показаны) - в 2 ряда по 2-3 карточки
            CardSection(title: i18n.t("expert.metrics"), icon: "chart.xyaxis.line") {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    // Первый ряд: SOH Energy, DCIR, Энергоэффективность
                    EnhancedStatCard(
                        title: i18n.t("soh.energy"),
                        value: getSOHEnergy(),
                        icon: "bolt.circle.fill",
                        accentColor: .green,
                        healthStatus: nil,
                        isCollectingData: analytics.lastAnalysis?.sohEnergy ?? 0 <= 0
                    )
                    .help(i18n.language == .ru ? "Реальная ёмкость батареи по сравнению с новой. Норма: >80%" : "Battery's real capacity compared to new. Normal: >80%")
                    EnhancedStatCard(
                        title: i18n.t("dcir.resistance"),
                        value: getDCIRValue(),
                        icon: "waveform.path.ecg",
                        accentColor: getDCIRHealthStatus()?.color == "green" ? .green : 
                                   getDCIRHealthStatus()?.color == "orange" ? .orange : 
                                   getDCIRHealthStatus()?.color == "red" ? .red : Color.accentColor,
                        healthStatus: getDCIRHealthStatus(),
                        isCollectingData: analytics.lastAnalysis?.dcirAt50Percent == nil
                    )
                    .help(i18n.language == .ru ? "Как быстро батарея реагирует на изменения нагрузки. Чем лучше, тем ниже значение" : "How quickly the battery responds to load changes. Lower values are better")
                    EnhancedStatCard(
                        title: i18n.t("energy.efficiency"),
                        value: getEnergyEfficiency(),
                        icon: "leaf.fill",
                        accentColor: getEnergyEfficiencyColor(),
                        isCollectingData: analytics.lastAnalysis?.sohEnergy ?? 0 <= 0
                    )
                    .help(i18n.language == .ru ? "Насколько эффективно батарея использует свою ёмкость. Норма: 85-100%" : "How efficiently the battery uses its capacity. Normal: 85-100%")
                    
                    // Второй ряд: Микро-дропы, Knee Index
                    EnhancedStatCard(
                        title: i18n.t("micro.drops"),
                        value: getMicroDrops(),
                        icon: "arrow.down.circle",
                        accentColor: getMicroDropHealthStatus()?.color == "green" ? .green : 
                                   getMicroDropHealthStatus()?.color == "orange" ? .orange : 
                                   getMicroDropHealthStatus()?.color == "red" ? .red : Color.accentColor,
                        healthStatus: getMicroDropHealthStatus(),
                        isCollectingData: false
                    )
                    .help(i18n.language == .ru ? "Резкие скачки заряда. 0 = отлично, >5 = проблема" : "Sudden charge drops. 0 = excellent, >5 = problem")
                    EnhancedStatCard(
                        title: i18n.t("knee.index"),
                        value: getKneeIndex(),
                        icon: "chart.line.uptrend.xyaxis.circle",
                        accentColor: .blue,
                        healthStatus: nil,
                        isCollectingData: analytics.lastAnalysis?.kneeIndex ?? 0 <= 0
                    )
                    .help(i18n.language == .ru ? "Насколько плавно разряжается батарея. 100 = идеально, <50 = проблемы" : "How smoothly the battery discharges. 100 = perfect, <50 = problems")
                }
            }
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
                StatCard(title: i18n.t("average.power"), value: i18n.language == .ru ? String(format: "%.1f Вт", analysis.averagePower) : String(format: "%.1f W", analysis.averagePower))
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
                    title: i18n.t("average.power"),
                    value: i18n.language == .ru ? String(format: "%.1f Вт", analysis.averagePower) : String(format: "%.1f W", analysis.averagePower),
                    icon: "bolt.fill",
                    accentColor: analysis.averagePower > 15 ? .orange : Color.accentColor
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
