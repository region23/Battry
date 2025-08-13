import Foundation
import Combine
import SwiftUI

@MainActor
final class BatteryViewModel: ObservableObject {
    @Published var state: BatterySnapshot = BatterySnapshot()

    var refreshInterval: TimeInterval = 30
    private var timer: AnyCancellable?

    let publisher = PassthroughSubject<BatterySnapshot, Never>()

    var menuBarSymbol: String {
        symbolForMenu(percent: state.percentage, charging: state.isCharging)
    }

    var symbolForCurrentLevel: String {
        symbolForIcon(percent: state.percentage, charging: state.isCharging)
    }

    var tintColor: Color {
        if state.isCharging { return .green }
        switch state.percentage {
        case 0..<20: return .red
        case 20..<50: return .orange
        default: return .accentColor
        }
    }

    var timeRemainingText: String {
        let L = Localization.shared
        if let tte = state.timeToEmptyMin, state.powerSource == .battery {
            return String(format: L.t("time.remaining"), format(minutes: tte))
        }
        if let ttf = state.timeToFullMin, state.isCharging {
            return String(format: L.t("time.to.full"), format(minutes: ttf))
        }
        return L.t("dash")
    }

    func start() {
        refresh()
        timer = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func refresh() {
        let snap = BatteryService.read()
        self.state = snap
        publisher.send(snap)
    }

    private func format(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return String(format: "%d:%02d", h, m)
    }

    private func symbolForMenu(percent: Int, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        switch percent {
        case 0..<10: return "battery.0"
        case 10..<25: return "battery.25"
        case 25..<50: return "battery.50"
        case 50..<75: return "battery.75"
        default: return "battery.100"
        }
    }

    private func symbolForIcon(percent: Int, charging: Bool) -> String {
        symbolForMenu(percent: percent, charging: charging)
    }
}

extension BatterySnapshot {
    var wearPercent: Double {
        guard designCapacity > 0 && maxCapacity > 0 else { return 0 }
        return max(0, (1.0 - Double(maxCapacity) / Double(designCapacity)) * 100.0)
    }
    
    var hasBattery: Bool {
        // Проверяем, есть ли у устройства батарея
        return BatteryService.hasBattery()
    }
}
