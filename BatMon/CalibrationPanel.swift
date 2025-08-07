import SwiftUI

struct CalibrationPanel: View {
    @ObservedObject var calibrator: CalibrationEngine
    @ObservedObject var history: HistoryStore
    let snapshot: BatterySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch calibrator.state {
            case .idle:
                Text("Калибровка позволит точнее оценить автономность и состояние батареи. \nМы соберём непрерывный разряд **100% → 20%**.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    calibrator.start()
                } label: {
                    Label("Начать калибровку", systemImage: "target")
                }
                .buttonStyle(.borderedProminent)

            case .waitingFull:
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "battery.100.bolt")
                        .foregroundColor(.primary)
                    Text("Зарядите до 100% и отключите питание. \nКалибровка стартует автоматически.")
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
                    Label("Идёт калибровка…", systemImage: "hourglass")
                    Text("Старт: \(start.formatted()) • c \(p)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Текущий заряд: \(snapshot.percentage)%")
                    Text("Цель: 20% (не подключайте питание)")
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
                    Text("Калибровка на паузе: питание подключено. \nОтключите питание и зарядите до 100% для перезапуска.")
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
                    Label("Калибровка завершена", systemImage: "checkmark.seal")
                    Text("Длительность: \(String(format: "%.2f", res.durationHours)) ч")
                    Text("Средний разряд: \(String(format: "%.1f", res.avgDischargePerHour)) %/ч")
                    Text("Оценка автономности 100→0%: \(String(format: "%.1f", res.estimatedRuntimeFrom100To0Hours)) ч")
                    HStack {
                        Button("Повторить") { calibrator.start() }
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
        }
    }
}
