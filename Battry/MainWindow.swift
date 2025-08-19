import SwiftUI

/// Основное окно приложения Battry
struct MainWindow: View {
    @ObservedObject var battery: BatteryViewModel
    @ObservedObject var history: HistoryStore
    @ObservedObject var analytics: AnalyticsEngine
    @ObservedObject var calibrator: CalibrationEngine
    @ObservedObject var loadGenerator: LoadGenerator
    @ObservedObject var safetyGuard: LoadSafetyGuard
    @ObservedObject var updateChecker: UpdateChecker
    @ObservedObject var windowState: WindowState
    
    var body: some View {
        MenuContent(
            battery: battery,
            history: history,
            analytics: analytics,
            calibrator: calibrator,
            loadGenerator: loadGenerator,
            safetyGuard: safetyGuard,
            updateChecker: updateChecker,
            initialPanel: windowState.activePanel,
            windowState: windowState
        )
        .frame(width: 720, height: 500)
        .navigationTitle("Battry")
    }
}