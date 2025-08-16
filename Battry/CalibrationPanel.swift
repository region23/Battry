import SwiftUI
import AppKit

/// Панель проведения теста/калибровки автономности
struct CalibrationPanel: View {
    @ObservedObject var calibrator: CalibrationEngine
    @ObservedObject var history: HistoryStore
    let snapshot: BatterySnapshot
    @ObservedObject var i18n: Localization = .shared
    

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            
            // Основная карточка состояния
            switch calibrator.state {
            case .idle:
                idleStateView
                
            case .waitingFull:
                waitingFullStateView
                
            case .running(let start, let p):
                runningStateView(start: start, startPercent: p)
                
            case .paused:
                pausedStateView
                
            case .completed(let res):
                completedStateView(result: res)
            }
            
            // Секция истории результатов
            if let last = calibrator.lastResult {
                lastResultSection(result: last)
            }
            
            if !calibrator.recentResults.isEmpty {
                recentResultsSection
            }
            
            Spacer()
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
}

// MARK: - State Views

extension CalibrationPanel {
    private var idleStateView: some View {
        CardSection(title: i18n.t("calibration.start.test"), icon: "target") {
            VStack(alignment: .leading, spacing: 10) {
                Text(i18n.t("analysis.intro"))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                
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
                    }
                }
                
                Button {
                    calibrator.start()
                } label: {
                    HStack {
                        Image(systemName: "target")
                        Text(i18n.t("analysis.start"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var waitingFullStateView: some View {
        let (message, needsUnplug) = {
            if snapshot.percentage >= 98 {
                if snapshot.isCharging || snapshot.powerSource == .ac {
                    return (i18n.t("analysis.unplug.to.start"), true)
                } else {
                    return (String(format: i18n.t("analysis.ready.at.percent"), snapshot.percentage), false)
                }
            } else {
                return (String(format: i18n.t("analysis.charge.to.percent"), snapshot.percentage), false)
            }
        }()
        
        return StatusCard(
            title: i18n.t("calibration.waiting.title"),
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
                
                Button(i18n.t("stop"), role: .destructive) {
                    showStopTestAlert()
                }
                .buttonStyle(.bordered)
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
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        } label: {
                            HStack {
                                Image(systemName: "doc.text")
                                Text(i18n.t("open.report"))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Button {
                        let analytics = AnalyticsEngine()
                        let analysis = analytics.analyze(history: history.recent(days: 7), snapshot: snapshot)
                        _ = ReportGenerator.generateHTML(result: analysis, snapshot: snapshot, history: history.recent(days: 7), calibration: result)
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text(i18n.t("save.to.report"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
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
    
    private func lastResultSection(result: CalibrationResult) -> some View {
        CardSection(title: i18n.t("last.result"), icon: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(result.startedAt.formatted(date: .abbreviated, time: .shortened))")
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(result.finishedAt.formatted(date: .abbreviated, time: .shortened))")
                    Spacer()
                }
                .font(.subheadline)
                .fontWeight(.medium)
                
                Text(String(format: i18n.t("last.result.line"), 
                           String(format: "%.1f", result.avgDischargePerHour), 
                           String(format: "%.1f", result.estimatedRuntimeFrom100To0Hours)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var recentResultsSection: some View {
        CardSection(title: i18n.t("recent.analyses"), icon: "list.bullet") {
            VStack(spacing: 8) {
                ForEach(Array(calibrator.recentResults.reversed()).prefix(5), id: \.finishedAt) { result in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: i18n.t("recent.line"),
                                        result.startedAt.formatted(date: .abbreviated, time: .shortened),
                                        result.finishedAt.formatted(date: .omitted, time: .shortened),
                                        String(format: "%.1f", result.avgDischargePerHour)))
                                .font(.caption)
                        }
                        
                        Spacer()
                        
                        if let path = result.reportPath {
                            Button {
                                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                            } label: {
                                Image(systemName: "doc.text")
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                    if result.finishedAt != calibrator.recentResults.reversed().prefix(5).last?.finishedAt {
                        Divider()
                    }
                }
            }
        }
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
    
    private func showStopTestAlert() {
        let alert = NSAlert()
        alert.messageText = i18n.t("calibration.stop.title")
        alert.informativeText = i18n.t("calibration.stop.confirm")
        alert.alertStyle = .warning
        alert.addButton(withTitle: i18n.t("calibration.continue"))  // Первая кнопка - продолжить
        alert.addButton(withTitle: i18n.t("calibration.stop.button"))  // Вторая кнопка - прервать
        
        // Устанавливаем деструктивную кнопку для прерывания
        if let stopButton = alert.buttons.last {
            stopButton.hasDestructiveAction = true
        }
        
        // Показываем alert и обрабатываем ответ
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            calibrator.stop()
        }
        // При выборе "Продолжить тест" (.alertFirstButtonReturn) ничего не делаем
    }
}
