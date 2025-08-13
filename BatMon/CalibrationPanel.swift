import SwiftUI

struct CalibrationPanel: View {
    @ObservedObject var calibrator: CalibrationEngine
    @ObservedObject var history: HistoryStore
    let snapshot: BatterySnapshot
    @ObservedObject var i18n: Localization = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch calibrator.state {
            case .idle:
                Text(i18n.t("analysis.intro"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    calibrator.start()
                } label: {
                    Label(i18n.t("analysis.start"), systemImage: "target")
                }
                .buttonStyle(.borderedProminent)

            case .waitingFull:
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
                    calibrator.stop()
                }
                .buttonStyle(.bordered)

            case .paused:
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
                    HStack {
                        Button(i18n.t("analysis.repeat")) { calibrator.start() }
                        Button(i18n.t("reset")) { calibrator.stop() }.buttonStyle(.bordered)
                    }
                }
            }

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
