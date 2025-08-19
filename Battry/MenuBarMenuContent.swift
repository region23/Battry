import SwiftUI

/// Содержимое меню в menu bar
struct MenuBarMenuContent: View {
    @ObservedObject var battery: BatteryViewModel
    @ObservedObject var i18n: Localization
    @ObservedObject var windowState: WindowState
    let setupServices: () -> Void
    
    var body: some View {
        VStack {
            Button(i18n.t("menu.open.battry")) {
                windowState.activateWindow(panel: .overview)
            }
            .keyboardShortcut("o", modifiers: .command)
            
            Divider()
            
            Button(i18n.t("menu.settings")) {
                windowState.activateWindow(panel: .settings)
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Button(i18n.t("menu.about")) {
                windowState.activateWindow(panel: .about)
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