import SwiftUI

/// Панель проведения теста/калибровки автономности
struct CalibrationPanel: View {
    @ObservedObject var calibrator: CalibrationEngine
    @ObservedObject var history: HistoryStore
    let snapshot: BatterySnapshot
    @ObservedObject var i18n: Localization = .shared
    @State private var confirmBrightness = false
    @State private var confirmBackground = false
    @State private var confirmLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Сообщение о сбросе сессии из‑за большого разрыва между сэмплами
            if calibrator.autoResetDueToGap {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.yellow)
                    Text(i18n.t("analysis.auto.reset"))
                        .font(.caption)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(i18n.t("got.it")) { calibrator.acknowledgeAutoResetNotice() }
                    .buttonStyle(.bordered)
            }
            switch calibrator.state {
            case .idle:
                // Состояние покоя: инструкция и чек‑лист перед стартом
                Text(i18n.t("analysis.intro"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(i18n.t("precheck.title")).font(.caption).foregroundStyle(.secondary)
                    Toggle(i18n.t("precheck.brightness"), isOn: $confirmBrightness)
                    Toggle(i18n.t("precheck.background"), isOn: $confirmBackground)
                    Toggle(i18n.t("precheck.load"), isOn: $confirmLoad)
                }
                Button {
                    // Переход в ожидание 100% (старт теста)
                    calibrator.start()
                } label: {
                    Label(i18n.t("analysis.start"), systemImage: "target")
                }
                .disabled(!(confirmBrightness && confirmBackground && confirmLoad))
                .buttonStyle(.borderedProminent)

            case .waitingFull:
                // Зарядите до 100% и отключите питание — тест стартует сам
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "battery.100.bolt")
                        .foregroundColor(.primary)
                    Text(i18n.t("analysis.waiting.full"))
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text(String(format: i18n.t("current.charge"), snapshot.percentage))
                    Spacer()
                }
                Button(i18n.t("cancel"), role: .destructive) {
                    calibrator.stop()
                }
                .buttonStyle(.bordered)

            case .running(let start, let p):
                // Идёт непрерывный разряд до 5%
                VStack(alignment: .leading, spacing: 6) {
                    Label(i18n.t("analysis.running"), systemImage: "hourglass")
                    Text("Старт: \(start.formatted()) • c \(p)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: i18n.t("current.charge"), snapshot.percentage))
                    Text(i18n.t("analysis.target"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(max(0, min(100, snapshot.percentage - 5))), total: 95)
                        .progressViewStyle(.linear)
                    if let eta = estimateETA(start: start, startPercent: p, currentPercent: snapshot.percentage) {
                        Text(String(format: i18n.t("eta"), eta))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Button(i18n.t("stop"), role: .destructive) {
                    // Прервать и сбросить текущую сессию
                    calibrator.stop()
                }
                .buttonStyle(.bordered)

            case .paused:
                // Пауза: питание подключено. Для продолжения — снова 100% на батарее
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "pause.circle")
                        .foregroundColor(.primary)
                    Text(i18n.t("analysis.paused"))
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(i18n.t("cancel"), role: .destructive) {
                    calibrator.stop()
                }
                .buttonStyle(.bordered)

            case .completed(let res):
                // Завершено: итоги и ссылка на отчёт
                VStack(alignment: .leading, spacing: 6) {
                    Label(i18n.t("analysis.done"), systemImage: "checkmark.seal")
                    Text(String(format: i18n.t("duration.hours"), String(format: "%.2f", res.durationHours)))
                    Text(String(format: i18n.t("avg.discharge.per.hour.val"), String(format: "%.1f", res.avgDischargePerHour)))
                    Text(String(format: i18n.t("runtime.100.0.val"), String(format: "%.1f", res.estimatedRuntimeFrom100To0Hours)))
                    if let path = res.reportPath {
                        Button(i18n.t("open.report")) {
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        }
                    }
                    Button(i18n.t("save.to.report")) {
                        // Сгенерировать отчёт по 7 дням и открыть
                        let analytics = AnalyticsEngine()
                        let analysis = analytics.analyze(history: history.recent(days: 7), snapshot: snapshot)
                        _ = ReportGenerator.generateHTML(result: analysis, snapshot: snapshot, history: history.recent(days: 7), calibration: res)
                    }
                    HStack {
                        Button(i18n.t("analysis.repeat")) { calibrator.start() }
                        Button(i18n.t("reset")) { calibrator.stop() }.buttonStyle(.bordered)
                    }
                }
            }

            // Последний результат (если есть)
            if let last = calibrator.lastResult {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(i18n.t("last.result"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(last.startedAt.formatted()) → \(last.finishedAt.formatted())")
                    Text(String(format: i18n.t("last.result.line"), String(format: "%.1f", last.avgDischargePerHour), String(format: "%.1f", last.estimatedRuntimeFrom100To0Hours)))
                }
            }

            // История последних анализов
            if !calibrator.recentResults.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(i18n.t("recent.analyses"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(calibrator.recentResults.reversed()).prefix(5), id: \.finishedAt) { r in
                        HStack {
                            Text(String(format: i18n.t("recent.line"),
                                        r.startedAt.formatted(date: .abbreviated, time: .shortened),
                                        r.finishedAt.formatted(date: .omitted, time: .shortened),
                                        String(format: "%.1f", r.avgDischargePerHour)))                                .font(.caption)
                            Spacer()
                            if let path = r.reportPath {
                                Button(i18n.t("open.report")) {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
            }
        }
    }

    private func estimateETA(start: Date, startPercent: Int, currentPercent: Int) -> String? {
        let elapsed = Date().timeIntervalSince(start) / 3600.0 // hours
        let d = Double(max(0, startPercent - currentPercent))
        guard elapsed > 0, d > 0 else { return nil }
        let rate = d / elapsed // % per hour
        guard rate > 0 else { return nil }
        let remaining = Double(max(0, currentPercent - 5))
        let hours = remaining / rate
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return String(format: "%d:%02d", h, m)
    }
}
