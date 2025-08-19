import SwiftUI
import Combine
import AppKit

/// Вкладки главного окна
enum Panel: String, CaseIterable, Identifiable {
    case overview
    case trends
    case test
    case settings
    case about
    var id: String { rawValue }
}

/// Состояние главного окна приложения
@MainActor
class WindowState: ObservableObject {
    /// Активная панель в окне
    @Published var activePanel: Panel
    
    /// Сохраняем в AppStorage
    @AppStorage("app.selectedPanel") private var storedPanel: Panel = .overview
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Читаем значение напрямую из UserDefaults для избежания использования self
        let savedPanelRaw = UserDefaults.standard.string(forKey: "app.selectedPanel") ?? "overview"
        let savedPanel = Panel(rawValue: savedPanelRaw) ?? .overview
        
        // Инициализируем activePanel значением из AppStorage
        self.activePanel = savedPanel
        
        // Синхронизируем изменения с AppStorage
        $activePanel
            .sink { [weak self] newPanel in
                self?.storedPanel = newPanel
            }
            .store(in: &cancellables)
    }
    
    /// Переключает на указанную панель
    func switchToPanel(_ panel: Panel) {
        activePanel = panel
    }
    
    /// Активирует главное окно приложения и переключается на панель
    func activateWindow(panel: Panel? = nil) {
        // Сначала переключаем панель, если указана
        if let panel = panel {
            activePanel = panel
        }
        
        // Активируем приложение
        NSApp.activate(ignoringOtherApps: true)
        
        // Находим главное окно приложения (первое обычное окно)
        let mainWindow = NSApp.windows.first { window in
            // Ищем окно с нашим содержимым (не системные окна)
            return window.contentView != nil && 
                   !window.styleMask.contains(.utilityWindow)
        }
        
        if let window = mainWindow {
            // Активируем найденное окно
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else {
            // Если главное окно не найдено, ничего не делаем
            // Приложение-агент обычно не создаёт новые окна программно
            print("Главное окно не найдено")
        }
    }
}