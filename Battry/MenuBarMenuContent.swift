import SwiftUI

/// Содержимое меню в menu bar
struct MenuBarMenuContent: View {
    @ObservedObject var battery: BatteryViewModel
    @ObservedObject var i18n: Localization
    @ObservedObject var windowState: WindowState
    let setupServices: () -> Void
    
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack {
            Button(i18n.t("menu.open.battry")) {
                windowState.switchToPanel(.overview)
                openWindow(id: "main")
            }
            .keyboardShortcut("o", modifiers: .command)
            
            Divider()
            
            Button(i18n.t("menu.settings")) {
                windowState.switchToPanel(.settings)
                openWindow(id: "main")
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Button(i18n.t("menu.about")) {
                windowState.switchToPanel(.about)
                openWindow(id: "main")
            }
            
            Divider()
            
            Button(i18n.t("menu.quit")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .onAppear {
            // Инициализируем все сервисы при первом показе меню
            setupServices()
        }
    }
}