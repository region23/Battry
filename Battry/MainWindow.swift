import SwiftUI
import AppKit

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
    @ObservedObject var quickHealthTest: QuickHealthTest
    
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
            windowState: windowState,
            quickHealthTest: quickHealthTest
        )
        .frame(width: 720, height: 500)
        .navigationTitle("Battry")
        .onAppear {
            setupWindowBehavior()
        }
    }
    
    /// Настраивает поведение окна - скрытие вместо закрытия
    private func setupWindowBehavior() {
        DispatchQueue.main.async {
            // Находим главное окно приложения
            if let window = NSApp.windows.first(where: { window in
                return window.contentView != nil && 
                       !window.styleMask.contains(.utilityWindow)
            }) {
                // Создаем и устанавливаем кастомный delegate
                let delegate = MainWindowDelegate()
                window.delegate = delegate
            }
        }
    }
}

/// Делегат для обработки событий главного окна
class MainWindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Вместо закрытия окна просто скрываем его
        sender.orderOut(nil)
        return false // Не закрываем окно
    }
}