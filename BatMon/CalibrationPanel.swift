import SwiftUI

struct CalibrationPanel: View {
    @ObservedObject var calibrator: CalibrationEngine
    @ObservedObject var history: HistoryStore
    let snapshot: BatterySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch calibrator.state {
            case .idle:
                Text("Анализ автономности: соберём непрерывный разряд **100% → 5%** и дадим понятный итоговый отчёт.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    calibrator.start()
                } label: {
                    Label("Начать анализ", systemImage: "target")
                }
                .buttonStyle(.borderedProminent)

            case .waitingFull:
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "battery.100.bolt")
                        .foregroundColor(.primary)
                    Text("Зарядите до 100% и отключите питание. \nАнализ стартует автоматически.")
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text("Текущий заряд: \(snapshot.percentage)%")
                    Spacer()
                }
                Button("Отмена", role: .destructive) {
                    calibrator.stop()
                }
                .buttonStyle(.bordered)

            case .running(let start, let p):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Идёт анализ…", systemImage: "hourglass")
                    Text("Старт: \(start.formatted()) • c \(p)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Текущий заряд: \(snapshot.percentage)%")
                    Text("Цель: 5% (не подключайте питание)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Прервать", role: .destructive) {
                    calibrator.stop()
                }
                .buttonStyle(.bordered)

            case .paused:
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "pause.circle")
                        .foregroundColor(.primary)
                    Text("Анализ на паузе: питание подключено. \nОтключите питание и зарядите до 100% для перезапуска.")
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Отмена", role: .destructive) {
                    calibrator.stop()
                }
                .buttonStyle(.bordered)

            case .completed(let res):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Анализ завершён", systemImage: "checkmark.seal")
                    Text("Длительность: \(String(format: "%.2f", res.durationHours)) ч")
                    Text("Средний разряд: \(String(format: "%.1f", res.avgDischargePerHour)) %/ч")
                    Text("Оценка автономности 100→0%: \(String(format: "%.1f", res.estimatedRuntimeFrom100To0Hours)) ч")
                    if let path = res.reportPath {
                        Button("Открыть HTML‑отчёт") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        }
                    }
                    HStack {
                        Button("Повторить анализ") { calibrator.start() }
                        Button("Сбросить") { calibrator.stop() }.buttonStyle(.bordered)
                    }
                }
            }

            if let last = calibrator.lastResult {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Последний результат")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(last.startedAt.formatted()) → \(last.finishedAt.formatted())")
                    Text("Средний разряд: \(String(format: "%.1f", last.avgDischargePerHour)) %/ч • Автономность: \(String(format: "%.1f", last.estimatedRuntimeFrom100To0Hours)) ч")
                }
            }

            if !calibrator.recentResults.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Последние анализы")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(calibrator.recentResults.reversed()).prefix(5), id: \.finishedAt) { r in
                        HStack {
                            Text("\(r.startedAt.formatted(date: .abbreviated, time: .shortened)) → \(r.finishedAt.formatted(time: .shortened)) • \(String(format: "%.1f", r.avgDischargePerHour)) %/ч")
                                .font(.caption)
                            Spacer()
                            if let path = r.reportPath {
                                Button("Открыть отчёт") {
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
}
