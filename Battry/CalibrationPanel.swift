import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Панель проведения теста/калибровки автономности
struct CalibrationPanel: View {
    @ObservedObject var battery: BatteryViewModel
    @ObservedObject var calibrator: CalibrationEngine
    @ObservedObject var history: HistoryStore
    @ObservedObject var analytics: AnalyticsEngine
    let snapshot: BatterySnapshot
    @ObservedObject var loadGenerator: LoadGenerator
    // Video load removed
    @ObservedObject var safetyGuard: LoadSafetyGuard
    @ObservedObject var i18n: Localization = .shared
    
    // Быстрый тест здоровья (экспертный протокол)
    @StateObject private var quickHealthTest = QuickHealthTest()
    
    // Используем настройки из CalibrationEngine вместо локального state
    private var selectedProfile: LoadProfile {
        get { calibrator.loadGeneratorSettings.profile }
        nonmutating set { calibrator.loadGeneratorSettings.profile = newValue }
    }
    
    private var enableLoadGenerator: Bool {
        get { calibrator.loadGeneratorSettings.isEnabled }
        nonmutating set { calibrator.loadGeneratorSettings.isEnabled = newValue }
    }
    
    // Video load removed
    
    private var autoStartGenerator: Bool {
        get { calibrator.loadGeneratorSettings.autoStart }
        nonmutating set { calibrator.loadGeneratorSettings.autoStart = newValue }
    }
    @State private var showHeavyProfileWarning: Bool = false
    @State private var showStopTestConfirm: Bool = false
    @State private var isAdvancedExpanded: Bool = false
    @State private var cpSelectedPreset: PowerPreset = .medium
    @AppStorage("settings.enableGPUBranch") private var enableGPUBranch: Bool = false
    

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Process indicator for all states
            processIndicator
            
            // Сообщение о сбросе сессии из‑за большого разрыва между сэмплами
            if calibrator.autoResetDueToGap {
                StatusCard(
                    title: i18n.t("calibration.auto.reset.title"),
                    subtitle: nil,
                    icon: "exclamationmark.triangle",
                    iconColor: .orange,
                    content: i18n.t("analysis.auto.reset")
                )
                Button(i18n.t("got.it")) { 
                    calibrator.acknowledgeAutoResetNotice() 
                }
                .buttonStyle(.borderedProminent)
            }
            
            // Предупреждение о высокой температуре
            if safetyGuard.hasTemperatureWarning {
                StatusCard(
                    title: i18n.t("temperature.warning.title"),
                    subtitle: nil,
                    icon: "thermometer",
                    iconColor: .orange,
                    content: String(format: i18n.t("temperature.warning.text"), safetyGuard.settings.warningTemperature)
                )
            }
            
            // Основная карточка состояния
            switch calibrator.state {
            case .idle:
                VStack(alignment: .leading, spacing: 10) {
                    // Отдельный блок: Быстрый тест здоровья
                    quickHealthTestSection
                    // Отдельный блок: Тест автономности
                    idleStateView
                    // Отдельный блок: Полный CP‑разряд до 5%
                    cpDischargeSection
                }
                
            case .waitingFull:
                waitingFullStateView
                
            case .running(let start, let p):
                runningStateView(start: start, startPercent: p)
                
            case .paused:
                pausedStateView
                
            case .completed(let res):
                completedStateView(result: res)
            }
            
            
            // Секция результатов анализов - отображается всегда
            analysisResultsSection
            
            Spacer()
        }
        .onChange(of: calibrator.state) { _, newState in
            // Stop load generator when calibration stops or completes
            if loadGenerator.isRunning {
                switch newState {
                case .idle, .completed:
                    loadGenerator.stop(reason: .userStopped)
                default:
                    break
                }
            }
        }
        .onAppear {
            // Инициализируем QuickHealthTest с зависимостями
            if !quickHealthTest.state.isActive {
                quickHealthTest.bind(
                    batteryViewModel: battery,
                    loadGenerator: loadGenerator
                )
            }
            // Включаем/выключаем GPU ветку в соответствии с настройкой
            loadGenerator.enableGPU(enableGPUBranch)
        }
        
    }

    private func estimateETA(start: Date, startPercent: Int, currentPercent: Int) -> String? {
        // Требуем минимум 15 минут и падение не менее 3%
        let elapsedSec = Date().timeIntervalSince(start)
        let elapsed = elapsedSec / 3600.0 // hours
        let d = Double(max(0, startPercent - currentPercent))
        guard elapsedSec >= 15 * 60, d >= 3 else { return nil }
        let rate = d / elapsed // % per hour
        guard rate > 0 else { return nil }
        let remaining = Double(max(0, currentPercent - 5))
        let hours = remaining / rate
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return String(format: "%d:%02d", h, m)
    }

    private func estimateEndTime(start: Date, startPercent: Int, currentPercent: Int) -> Date? {
        // Требуем минимум 15 минут и падение не менее 3%
        let elapsedSec = Date().timeIntervalSince(start)
        let elapsedHours = elapsedSec / 3600.0
        let discharged = Double(max(0, startPercent - currentPercent))
        guard elapsedSec >= 15 * 60, discharged >= 3 else { return nil }
        let rate = discharged / elapsedHours // % per hour
        guard rate > 0 else { return nil }
        let remainingPercent = Double(max(0, currentPercent - 5))
        let remainingHours = remainingPercent / rate
        return Date().addingTimeInterval(remainingHours * 3600.0)
    }

    private func hasEnoughData(start: Date, startPercent: Int, currentPercent: Int) -> Bool {
        let elapsedSec = Date().timeIntervalSince(start)
        let dropped = Double(max(0, startPercent - currentPercent))
        return elapsedSec >= 15 * 60 && dropped >= 3
    }
    
    /// Регенерирует HTML отчет с данными из сохраненного JSON и открывает его
    private func regenerateAndOpenReport(result: CalibrationResult, originalPath: String) {
        // Попытаться загрузить сохраненные данные теста
        var sessionHistory: [BatteryReading]
        var finalSnapshot: BatterySnapshot
        var loadMetadata: ReportGenerator.LoadGeneratorMetadata?
        
        if let dataPath = result.dataPath,
           let testData = calibrator.loadTestData(from: dataPath) {
            // Используем сохраненные данные из JSON файла
            sessionHistory = testData.samples
            finalSnapshot = testData.finalSnapshot
            loadMetadata = testData.loadGeneratorMetadata
            print("Using saved test data from: \(dataPath)")
        } else {
            // Fallback для старых отчетов без сохраненных данных
            sessionHistory = history.between(from: result.startedAt, to: result.finishedAt)
            finalSnapshot = snapshot
            loadMetadata = calibrator.currentLoadMetadata
            print("Using fallback: current data for legacy report")
        }
        
        // Генерируем анализ на основе сохраненных (или текущих) данных
        let analysis = analytics.analyze(history: sessionHistory, snapshot: finalSnapshot)
        
        // Генерируем HTML контент
        if let htmlContent = ReportGenerator.generateHTMLContent(
            result: analysis,
            snapshot: finalSnapshot,
            history: sessionHistory,
            calibration: result,
            loadGeneratorMetadata: loadMetadata
        ) {
            // Перезаписываем существующий файл
            let reportURL = URL(fileURLWithPath: originalPath)
            
            do {
                try htmlContent.write(to: reportURL, atomically: true, encoding: .utf8)
                print("Report regenerated successfully at: \(originalPath)")
                
                // Открываем обновленный отчет
                NSWorkspace.shared.open(reportURL)
            } catch {
                print("Failed to regenerate report: \(error)")
                
                // Если не удалось перезаписать, пытаемся открыть существующий файл
                NSWorkspace.shared.open(reportURL)
            }
        } else {
            print("Failed to generate HTML content for report")
            
            // Если не удалось сгенерировать, пытаемся открыть существующий файл
            NSWorkspace.shared.open(URL(fileURLWithPath: originalPath))
        }
    }
}

// MARK: - State Views

extension CalibrationPanel {
    private var cpDischargeSection: some View {
        CardSection(title: i18n.language == .ru ? "Полный CP‑разряд до 5%" : "Full CP Discharge to 5%", icon: "battery.25") {
            VStack(alignment: .leading, spacing: 8) {
                Text(i18n.language == .ru ? "Стандартизированный разряд при постоянной мощности до 5% с прогнозируемым временем." : "Standardized constant-power discharge down to 5% with reproducible runtime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    PowerPresetSelector(
                        selectedPreset: $cpSelectedPreset,
                        designCapacityMah: snapshot.designCapacity
                    )
                    .frame(maxWidth: 260)

                    Spacer()

                    Button {
                        calibrator.startCPDischarge(preset: cpSelectedPreset)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                            Text(i18n.language == .ru ? "Старт CP‑разряда" : "Start CP Discharge")
                            let nominalV = 11.1
                            let targetW = PowerCalculator.targetPower(for: cpSelectedPreset, designCapacityMah: snapshot.designCapacity, nominalVoltage: nominalV)
                            Text(String(format: "(%.1fW)", targetW))
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(snapshot.isCharging || snapshot.powerSource == .ac || snapshot.percentage < 98)
                }

                if snapshot.percentage < 98 {
                    Text(i18n.language == .ru ? "Требуется ≥98% и питание отключено" : "Requires ≥98% and unplugged")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if snapshot.isCharging || snapshot.powerSource == .ac {
                    Text(i18n.language == .ru ? "Отключите питание" : "Disconnect power")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
    private var idleStateView: some View {
        CardSection(title: i18n.t("calibration.start.test"), icon: "target") {
            VStack(alignment: .leading, spacing: 10) {
                Text(i18n.t("analysis.intro"))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "checklist")
                            .foregroundStyle(.orange)
                        Text(i18n.t("precheck.title"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        checklistItem(i18n.t("precheck.brightness"))
                        checklistItem(i18n.t("precheck.background"))  
                        checklistItem(i18n.t("precheck.load"))
                        checklistItem(i18n.t("precheck.network"))
                        checklistItem(i18n.t("precheck.temperature"))
                        if enableLoadGenerator {
                            checklistItem(i18n.t("precheck.load.generator"))
                        }
                    }
                }
                
                // Advanced Settings Section (Collapsible)
                advancedSettingsSection
                
                Button {
                    calibrator.start()
                    // Auto-start load generator if enabled
                    if autoStartGenerator && enableLoadGenerator {
                        loadGenerator.start(profile: selectedProfile)
                    }
                    // Auto-start video load if enabled
                    // video load removed
                } label: {
                    HStack {
                        Image(systemName: "target")
                            .font(.system(size: 16, weight: .semibold))
                        Text(i18n.t("analysis.start"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var waitingFullStateView: some View {
        let (title, message, needsUnplug) = {
            if snapshot.percentage >= 98 {
                if snapshot.isCharging || snapshot.powerSource == .ac {
                    return (i18n.t("calibration.battery.ready"), i18n.t("analysis.unplug.to.start"), true)
                } else {
                    // Это состояние не должно долго существовать - тест должен автоматически запуститься
                    return (i18n.t("calibration.waiting.title"), i18n.t("analysis.unplug.to.start"), false)
                }
            } else {
                return (i18n.t("calibration.waiting.title"), String(format: i18n.t("analysis.charge.to.percent"), snapshot.percentage), false)
            }
        }()
        
        return StatusCard(
            title: title,
            subtitle: nil,
            icon: needsUnplug ? "bolt.slash" : "battery.100.bolt",
            iconColor: needsUnplug ? .orange : .blue,
            content: message
        ) {
            Button(i18n.t("cancel"), role: .destructive) {
                calibrator.stop()
            }
            .buttonStyle(.bordered)
        }
    }
    
    private func runningStateView(start: Date, startPercent: Int) -> some View {
        CardSection(title: i18n.t("calibration.running.title"), icon: "hourglass") {
            VStack(alignment: .leading, spacing: 10) {
                // Информация о тесте
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(i18n.t("calibration.started.at"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(start.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text(i18n.t("calibration.start.percent"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(startPercent)%")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                
                SpacedDivider(padding: 4)
                
                // Прогресс
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(i18n.t("calibration.progress"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(max(0, startPercent - snapshot.percentage))/\(startPercent - 5) %")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.accentColor)
                    }
                    
                    EnhancedProgressView(
                        value: Double(max(0, min(startPercent - 5, startPercent - snapshot.percentage))),
                        total: Double(max(1, startPercent - 5)),
                        height: 12
                    )
                    
                    Text(i18n.t("analysis.target"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // ETA информация
                if hasEnoughData(start: start, startPercent: startPercent, currentPercent: snapshot.percentage) {
                    SpacedDivider(padding: 4)
                    etaInfoView(start: start, startPercent: startPercent)
                } else {
                    SpacedDivider(padding: 4)
                    Text(i18n.t("eta.pending"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
                
                // Load Generator Status during running test
                if enableLoadGenerator || loadGenerator.isRunning {
                    SpacedDivider(padding: 4)
                    loadGeneratorStatusView
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Button(i18n.t("cancel.test"), role: .destructive) {
                        showStopTestConfirm = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    if showStopTestConfirm {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(i18n.t("calibration.stop.title"))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            Text(i18n.t("calibration.stop.confirm"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                Button(i18n.t("calibration.stop.button"), role: .destructive) {
                                    calibrator.stop()
                                    if loadGenerator.isRunning {
                                        loadGenerator.stop(reason: .userStopped)
                                    }
                                    // video load removed
                                    showStopTestConfirm = false
                                }
                                .buttonStyle(.borderedProminent)
                                Button(i18n.t("calibration.continue"), role: .cancel) {
                                    showStopTestConfirm = false
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(8)
                        .background(
                            .regularMaterial,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }
                }
            }
        }
    }
    
    private var pausedStateView: some View {
        StatusCard(
            title: i18n.t("calibration.paused.title"),
            subtitle: nil,
            icon: "pause.circle",
            iconColor: .orange,
            content: i18n.t("analysis.paused")
        ) {
            Button(i18n.t("cancel"), role: .destructive) {
                calibrator.stop()
            }
            .buttonStyle(.bordered)
        }
    }
    
    private func completedStateView(result: CalibrationResult) -> some View {
        CardSection(title: i18n.t("calibration.completed.title"), icon: "checkmark.seal") {
            VStack(alignment: .leading, spacing: 10) {
                // Результаты теста
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ], spacing: 6) {
                    EnhancedStatCard(
                        title: i18n.t("calibration.duration"),
                        value: String(format: "%.1fч", result.durationHours),
                        icon: "clock"
                    )
                    EnhancedStatCard(
                        title: i18n.t("calibration.avg.discharge"),
                        value: String(format: "%.1f%%/ч", result.avgDischargePerHour),
                        icon: "speedometer"
                    )
                }
                
                EnhancedStatCard(
                    title: i18n.t("calibration.estimated.runtime"),
                    value: String(format: "%.1fч", result.estimatedRuntimeFrom100To0Hours),
                    icon: "battery.0",
                    accentColor: result.estimatedRuntimeFrom100To0Hours < 3 ? .red : Color.accentColor
                )
                
                SpacedDivider()
                
                // Действия
                VStack(spacing: 8) {
                    if let path = result.reportPath {
                        Button {
                            regenerateAndOpenReport(result: result, originalPath: path)
                        } label: {
                            HStack {
                                Image(systemName: "doc.text")
                                Text(i18n.t("open.report"))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            // Save as PDF
                            let panel = NSSavePanel()
                            panel.allowedContentTypes = [.pdf]
                            panel.nameFieldStringValue = "Battry_Report.pdf"
                            panel.begin { resp in
                                if resp == .OK, let dest = panel.url {
                                    ReportGenerator.exportHTMLToPDF(htmlURL: URL(fileURLWithPath: path), destinationURL: dest) { ok in
                                        if ok { NSWorkspace.shared.open(dest) }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text(i18n.t("export.pdf"))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    
                    HStack(spacing: 8) {
                        Button(i18n.t("analysis.repeat")) { 
                            calibrator.start() 
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button(i18n.t("reset")) { 
                            calibrator.stop() 
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
    
    
    private var analysisResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "list.bullet")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text(i18n.t("analysis.results"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            // Quick Health Test - last result (if available)
            if let quick = quickHealthTest.lastResult {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundStyle(.green)
                        Text(i18n.t("quick.health.test"))
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Text(String(format: "%.1f %@", quick.durationMinutes, i18n.language == .ru ? "мин" : "min"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(String(format: "%.0f", quick.healthScore))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(quick.healthScore >= 85 ? .green : quick.healthScore >= 70 ? .orange : .red)
                            Text(i18n.t("health"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Divider().frame(height: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(String(format: "%.1f%%", quick.sohEnergy))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(i18n.t("soh.energy"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let dcir50 = quick.dcirAt50Percent {
                            Divider().frame(height: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(String(format: "%.0f", dcir50))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text(i18n.language == .ru ? "мОм" : "mΩ")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(i18n.language == .ru ? "Отчёт" : "Report") {
                            generateQuickHealthReport(result: quick)
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.regularMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.green.opacity(0.15), lineWidth: 1)
                        )
                )
            }
            
            if !calibrator.recentResults.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(calibrator.recentResults.reversed()).prefix(5), id: \.finishedAt) { result in
                        enhancedResultCard(for: result)
                    }
                }
            } else {
                // Показываем подсказку когда нет результатов
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary.opacity(0.6))
                    
                    Text(i18n.t("analysis.results.empty.with.report"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
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
    }
    
    private func checklistItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(.blue)
                .frame(width: 4, height: 4)
                .padding(.top, 6)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private func etaInfoView(start: Date, startPercent: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let eta = estimateETA(start: start, startPercent: startPercent, currentPercent: snapshot.percentage) {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.blue)
                    Text(String(format: i18n.t("eta"), eta))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                }
            }
            
            if let endAt = estimateEndTime(start: start, startPercent: startPercent, currentPercent: snapshot.percentage) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.blue)
                    Text(String(format: i18n.t("eta.end.at"), endAt.formatted(date: .omitted, time: .shortened)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            
            Text(i18n.t("eta.note"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .italic()
        }
    }
    
    
    
}


// MARK: - Load Generator Controls

extension CalibrationPanel {
    
    private var processIndicator: some View {
        let steps = [
            ProcessStep(title: i18n.t("process.step.prepare")),
            ProcessStep(title: i18n.t("process.step.charge")),
            ProcessStep(title: i18n.t("process.step.test")),
            ProcessStep(title: i18n.t("process.step.results"))
        ]
        
        let currentStep: Int = {
            switch calibrator.state {
            case .idle:
                return 0
            case .waitingFull:
                return 1
            case .running, .paused:
                return 2
            case .completed:
                return 3
            }
        }()
        
        return ProcessStepIndicator(steps: steps, currentStep: currentStep)
    }
    
    private var advancedSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isAdvancedExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "gear")
                        .foregroundStyle(.secondary)
                    Text(i18n.t("advanced.settings.title"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12, weight: .medium))
                        .rotationEffect(.degrees(isAdvancedExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.25), value: isAdvancedExpanded)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.3))
            )
            
            if isAdvancedExpanded {
                loadGeneratorControls
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
    }
    
    private var loadGeneratorControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "cpu")
                    .foregroundStyle(.orange)
                Text(i18n.t("load.generator.title"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle(i18n.t("load.generator.enable"), isOn: Binding(
                    get: { enableLoadGenerator },
                    set: { enableLoadGenerator = $0 }
                ))
                    .toggleStyle(.checkbox)
                
                if enableLoadGenerator {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(i18n.t("load.generator.profile"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 8) {
                            ForEach([LoadProfile.light, LoadProfile.medium, LoadProfile.heavy], id: \.localizationKey) { profile in
                                Button {
                                    if profile.localizationKey == LoadProfile.heavy.localizationKey {
                                        showHeavyProfileWarning = true
                                    } else {
                                        selectedProfile = profile
                                    }
                                } label: {
                                    Text(i18n.t(profile.localizationKey))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            selectedProfile.localizationKey == profile.localizationKey ? Color.accentColor : Color.clear,
                                            in: Capsule()
                                        )
                                        .foregroundStyle(selectedProfile.localizationKey == profile.localizationKey ? .white : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if showHeavyProfileWarning {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "bolt.fill")
                                        .foregroundStyle(Color.accentColor)
                                    Text(i18n.t("heavy.profile.warning.title"))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                Text(i18n.t("heavy.profile.warning.message"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 8) {
                                    Button(i18n.t("heavy.profile.warning.continue"), role: .destructive) {
                                        selectedProfile = .heavy
                                        showHeavyProfileWarning = false
                                    }
                                    .buttonStyle(.borderedProminent)
                                    Button(i18n.t("heavy.profile.warning.cancel"), role: .cancel) {
                                        showHeavyProfileWarning = false
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(8)
                            .background(
                                .regularMaterial,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                        }
                        
                        Toggle(i18n.t("load.generator.auto.start"), isOn: Binding(
                            get: { autoStartGenerator },
                            set: { autoStartGenerator = $0 }
                        ))
                            .toggleStyle(.checkbox)
                            .font(.caption)

                        Toggle(i18n.t("load.generator.enable.gpu"), isOn: Binding(
                            get: { enableGPUBranch },
                            set: { enabled in enableGPUBranch = enabled; loadGenerator.enableGPU(enabled) }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    }
                }
                
                // Video load section removed
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
    
    private var loadGeneratorStatusView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "cpu")
                    .foregroundStyle(loadGenerator.isRunning ? .green : .secondary)
                Text(i18n.t("load.generator.status"))
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                
                if loadGenerator.isRunning {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(.green, lineWidth: 1)
                                .scaleEffect(1.5)
                                .opacity(0.5)
                        )
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: loadGenerator.isRunning)
                }
            }
            
            if loadGenerator.isRunning {
                if let profile = loadGenerator.currentProfile {
                    Text(String(format: i18n.t("load.generator.running.profile"), i18n.t(profile.localizationKey)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 8) {
                    Button(i18n.t("load.generator.pause")) {
                        loadGenerator.stop(reason: .userStopped)
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            } else if let reason = loadGenerator.lastStopReason {
                if case .userStopped = reason {
                    Text(i18n.t("load.generator.stopped"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption2)
                        Text(getStopReasonText(reason))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            // Video load status removed
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
    
    private func getStopReasonText(_ reason: LoadStopReason) -> String {
        switch reason {
        case .lowBattery(let percentage):
            return String(format: i18n.t("load.stop.battery.text"), percentage)
        case .highTemperature(let temp):
            return String(format: i18n.t("load.stop.temperature.text"), temp)
        case .thermalPressure(let state):
            let stateText = state == .critical ? i18n.t("thermal.critical") : i18n.t("thermal.serious")
            return String(format: i18n.t("load.stop.thermal.text"), stateText)
        case .powerConnected:
            return i18n.t("load.stop.power.text")
        case .charging:
            return i18n.t("load.stop.charging.text")
        case .userStopped:
            return i18n.t("load.generator.stopped")
        }
    }
    
    private func enhancedResultCard(for result: CalibrationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with date and time
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.startedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 4) {
                        Text(result.startedAt.formatted(date: .omitted, time: .shortened))
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                        Text(result.finishedAt.formatted(date: .omitted, time: .shortened))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Mini trend visualization
                let sessionHistory = history.between(from: result.startedAt, to: result.finishedAt)
                let percentages = sessionHistory.map { Double($0.percentage) }
                
                VStack(alignment: .trailing, spacing: 2) {
                    if !percentages.isEmpty {
                        MiniSparkline(
                            values: percentages,
                            color: result.estimatedRuntimeFrom100To0Hours < 3 ? .red : Color.accentColor,
                            height: 16
                        )
                        .frame(width: 40)
                        
                        Text("\(percentages.first?.formatted(.number.precision(.fractionLength(0))) ?? "--")% → \(percentages.last?.formatted(.number.precision(.fractionLength(0))) ?? "-")%")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            
            // Key metrics in compact grid
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(format: "%.1f %%/ч", result.avgDischargePerHour))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                    Text(i18n.t("discharge.rate"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                    .frame(height: 20)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(format: "%.1f ч", result.estimatedRuntimeFrom100To0Hours))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(result.estimatedRuntimeFrom100To0Hours < 3 ? .red : .primary)
                    Text(i18n.t("runtime.estimated"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Report button
                if let path = result.reportPath {
                    Button {
                        regenerateAndOpenReport(result: result, originalPath: path)
                    } label: {
                        Image(systemName: "doc.text")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.borderless)
                    .help(i18n.t("reports.open"))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.accentColor.opacity(0.1), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let path = result.reportPath {
                regenerateAndOpenReport(result: result, originalPath: path)
            }
        }
    }
    
    // MARK: - Quick Health Test Section
    
    @ViewBuilder
    private var quickHealthTestSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .foregroundStyle(.green)
                Text(i18n.t("quick.health.test"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                
                // Badge показывающий, что это экспертная функция
                Text("Expert")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green, in: Capsule())
            }
            
            Text(i18n.language == .ru ? "30-40 минут вместо полной разрядки (рекомендация эксперта)" : "30-40 minutes instead of full discharge (expert recommendation)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Состояние теста
            switch quickHealthTest.state {
            case .idle:
                HStack(spacing: 10) {
                    Button(i18n.language == .ru ? "Запустить быстрый тест" : "Start Quick Test") {
                        startQuickHealthTest()
                    }
                    .buttonStyle(.bordered)
                    .disabled(snapshot.percentage < 85 || snapshot.isCharging || snapshot.powerSource == .ac)
                    
                    Spacer(minLength: 8)
                    PowerPresetSelector(
                        selectedPreset: Binding(
                            get: { quickHealthTestSelectedPreset },
                            set: { newPreset in setQuickHealthPreset(newPreset) }
                        ),
                        designCapacityMah: snapshot.designCapacity
                    )
                    .frame(maxWidth: 260)

                    if snapshot.percentage < 85 {
                        Text(i18n.language == .ru ? "Требуется ≥85%" : "Requires ≥85%")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if snapshot.isCharging || snapshot.powerSource == .ac {
                        Text(i18n.language == .ru ? "Отключите питание" : "Disconnect power")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                
            case .calibrating:
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    VStack(alignment: .leading) {
                        Text(i18n.language == .ru ? "Калибровка в покое..." : "Baseline calibration...")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(String(format: "%.0f%%", quickHealthTest.progress * 100))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(i18n.t("stop")) {
                        quickHealthTest.stop()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
                
            case .pulseTesting(let targetSOC):
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    VStack(alignment: .leading) {
                        Text(i18n.language == .ru ? "Пульс-тест @\(targetSOC)%" : "Pulse test @\(targetSOC)%")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(String(format: "%.0f%%", quickHealthTest.progress * 100))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(i18n.t("stop")) {
                        quickHealthTest.stop()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
                
            case .energyWindow:
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    VStack(alignment: .leading) {
                        Text(i18n.language == .ru ? "Энергетическое окно 80→50%" : "Energy window 80→50%")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(String(format: "%.0f%%", quickHealthTest.progress * 100))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    PowerControlQualityIndicator(quality: Double(quickHealthCPQuality), isActive: true)
                    Button(i18n.t("stop")) {
                        quickHealthTest.stop()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
                
            case .analyzing:
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(i18n.language == .ru ? "Анализ результатов..." : "Analyzing results...")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                }
                
            case .completed(let result):
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(i18n.language == .ru ? "Тест завершён" : "Test completed")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Text(String(format: "%.1f %@", result.durationMinutes, i18n.language == .ru ? "мин" : "min"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 12) {
                        // Health Score
                        VStack {
                            Text(String(format: "%.0f", result.healthScore))
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(result.healthScore >= 85 ? .green : result.healthScore >= 70 ? .orange : .red)
                            Text(i18n.language == .ru ? "Скор" : "Score")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        // SOH Energy
                        VStack {
                            Text(String(format: "%.1f%%", result.sohEnergy))
                                .font(.caption)
                                .fontWeight(.bold)
                            Text(i18n.language == .ru ? "SOH" : "SOH")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        // DCIR @50%
                        if let dcir50 = result.dcirAt50Percent {
                            VStack {
                                Text(String(format: "%.0f", dcir50))
                                    .font(.caption)
                                    .fontWeight(.bold)
                                Text(i18n.language == .ru ? "мОм" : "mΩ")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button(i18n.language == .ru ? "Отчёт" : "Report") {
                            generateQuickHealthReport(result: result)
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
                
            case .error(let message):
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button(i18n.language == .ru ? "Повторить" : "Retry") {
                        quickHealthTest.start()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.green.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.green.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Quick Health Test Actions
    
    private func startQuickHealthTest() {
        // Простая заглушка для теста - нужно будет подключить правильные зависимости
        quickHealthTest.start()
    }
    
    private func generateQuickHealthReport(result: QuickHealthTest.QuickHealthResult) {
        // Генерируем HTML отчёт с результатами QuickHealthTest
        let analysis = analytics.analyze(history: history.items, snapshot: snapshot)
        
        if let reportURL = ReportGenerator.generateHTML(
            result: analysis,
            snapshot: snapshot,
            history: history.items,
            calibration: nil,
            quickHealthResult: result
        ) {
            NSWorkspace.shared.open(reportURL)
        }
    }
}

// MARK: - Quick Health Test Actions

extension CalibrationPanel {
    // Bridge helpers to control QuickHealthTest preset from UI
    private var quickHealthTestSelectedPreset: PowerPreset {
        // QuickHealthTest does not expose preset publicly; mirror via local state if needed.
        // For now, default to .medium; UI writes back through setQuickHealthPreset.
        .medium
    }
    private func setQuickHealthPreset(_ preset: PowerPreset) {
        quickHealthTest.setPowerPreset(preset)
    }
    private var quickHealthCPQuality: Int {
        // No direct binding to controller here; show placeholder 0..100 based on last analysis if available
        return Int(quickHealthTest.lastResult?.powerControlQuality ?? 0)
    }
}
