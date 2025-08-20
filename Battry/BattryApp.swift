import SwiftUI
import Combine
import AppKit

/// Главная точка входа в приложение Battry
@main
struct BattryApp: App {
    
    init() {
        // Проверяем и завершаем другие экземпляры приложения при запуске
        terminateOtherInstances()
    }
    /// ViewModel с текущим состоянием батареи
    @StateObject private var battery = BatteryViewModel()
    /// Хранилище истории измерений для графиков и аналитики
    @StateObject private var history = HistoryStore()
    /// Движок аналитики (оценки, тренды, рекомендации)
    @StateObject private var analytics = AnalyticsEngine()
    /// Движок калибровки/теста автономности
    @StateObject private var calibrator = CalibrationEngine()
    /// Генератор CPU нагрузки
    @StateObject private var loadGenerator = LoadGenerator()
    // Video load removed
    /// Охранник безопасности генератора
    @StateObject private var safetyGuard = LoadSafetyGuard { _ in
        // Callback будет настроен позже в onAppear
    }
    /// Проверка обновлений
    @StateObject private var updateChecker = UpdateChecker()
    /// Локализация (переключение языка в UI)
    @StateObject private var i18n = Localization.shared
    /// Состояние главного окна
    @StateObject private var windowState = WindowState()
    /// Быстрый тест здоровья (экспертный протокол)
    @StateObject private var quickHealthTest = QuickHealthTest()
    
    /// Настройка отображения процента в меню баре
    @AppStorage("settings.showPercentageInMenuBar") private var showPercentageInMenuBar: Bool = false

    var body: some Scene {
        // Основное окно приложения - используем handlesExternalEvents для единственности
        WindowGroup(id: "main") {
            MainWindow(
                battery: battery,
                history: history,
                analytics: analytics,
                calibrator: calibrator,
                loadGenerator: loadGenerator,
                safetyGuard: safetyGuard,
                updateChecker: updateChecker,
                windowState: windowState,
                quickHealthTest: quickHealthTest
            )
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 720, height: 500)
        .handlesExternalEvents(matching: ["main"])
        .commands {
            CommandGroup(replacing: .newItem) {
                // Заменяем стандартные команды меню на наши
            }
        }
        
        // Меню в строке меню
        MenuBarExtra {
            MenuBarMenuContent(
                battery: battery,
                i18n: i18n,
                windowState: windowState,
                setupServices: setupServices
            )
        } label: {
            HStack(spacing: 4) {
                if let iconName = getMenuBarIcon() {
                    Image(iconName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "battery.100")
                        .symbolRenderingMode(.hierarchical)
                }
                
                if showPercentageInMenuBar {
                    Text("\(Int(battery.state.percentage))%")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.menu)
        .onChange(of: battery.state) { oldValue, newValue in
            // На каждое обновление состояния добавляем точку в историю
            history.append(from: newValue)
        }
    }
    
    /// Настраивает все сервисы приложения
    private func setupServices() {
        // Инициализируем опрос батареи
        battery.start()
        history.start()
        calibrator.bind(to: battery.publisher, viewModel: battery)
        calibrator.attachHistory(history)
        calibrator.attachLoadGenerators(cpu: loadGenerator)
        
        // Настраиваем callback для safetyGuard
        safetyGuard.setStopCallback { reason in
            Task { @MainActor in
                loadGenerator.stop(reason: reason)
            }
        }
        
        // Связываем генератор нагрузки с охранником безопасности
        safetyGuard.startMonitoring(batteryPublisher: battery.publisher)
        
        // Инициализируем QuickHealthTest с зависимостями
        quickHealthTest.bind(
            batteryViewModel: battery,
            loadGenerator: loadGenerator
        )
    }
    
    
    /// Выбирает иконку для строки меню
    private func getMenuBarIcon() -> String? {
        // Используем кастомные иконки в зависимости от состояния зарядки
        return battery.state.powerSource == .ac ? "charge-icon" : "battery-icon"
    }
    
    /// Завершает другие запущенные экземпляры приложения
    private func terminateOtherInstances() {
        let bundleID = Bundle.main.bundleIdentifier ?? "region23.Battry"
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            // Ищем другие экземпляры нашего приложения (не текущий процесс)
            if app.bundleIdentifier == bundleID && app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                app.terminate()
            }
        }
    }
}

