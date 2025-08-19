import SwiftUI
import Combine

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
}