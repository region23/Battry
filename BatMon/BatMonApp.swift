import SwiftUI
import Combine

@main
struct BatMonApp: App {
    @StateObject private var battery = BatteryViewModel()
    @StateObject private var history = HistoryStore()
    @StateObject private var analytics = AnalyticsEngine()
    @StateObject private var calibrator = CalibrationEngine()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(battery: battery, history: history, analytics: analytics, calibrator: calibrator)
                .frame(width: 420)
                .onAppear {
                    battery.start()
                    history.start()
                    calibrator.bind(to: battery.publisher)
                }
                .onDisappear {
                    battery.stop()
                    history.stop()
                    calibrator.unbind()
                }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: getMenuBarIcon())
                    .symbolRenderingMode(.hierarchical)
                if shouldShowBatteryPercentage() {
                    Text("\(battery.state.percentage)%")
                        .font(.system(size: 11))
                }
            }
        }
        .menuBarExtraStyle(.window)
        .onChange(of: battery.state) { oldValue, newValue in
            history.append(from: newValue)
        }
    }
    
    private func getMenuBarIcon() -> String {
        // Если устройство не имеет батареи, показываем иконку вилки
        if !battery.state.hasBattery {
            return "powerplug"
        }
        
        // Если устройство имеет батарею, используем обычную логику
        return battery.state.powerSource == .ac ? "powerplug" : battery.menuBarSymbol
    }
    
    private func shouldShowBatteryPercentage() -> Bool {
        // Показываем проценты только если устройство имеет батарею
        return battery.state.hasBattery
    }
}
