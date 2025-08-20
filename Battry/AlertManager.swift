import SwiftUI
import Combine

/// Centralized alert management for the application
@MainActor
class AlertManager: ObservableObject {
    static let shared = AlertManager()
    
    @Published var isAlertPresented = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    @Published var alertType: AlertType = .info
    @Published var primaryAction: (() -> Void)?
    @Published var secondaryAction: (() -> Void)?
    @Published var primaryButtonText = ""
    @Published var secondaryButtonText = ""
    
    private let i18n = Localization.shared
    
    private init() {}
    
    enum AlertType {
        case info
        case warning
        case error
        case confirmation
    }
    
    /// Show a simple info alert
    func showInfo(title: String, message: String) {
        self.alertTitle = title
        self.alertMessage = message
        self.alertType = .info
        self.primaryAction = nil
        self.secondaryAction = nil
        self.primaryButtonText = i18n.t("ok")
        self.secondaryButtonText = ""
        self.isAlertPresented = true
    }
    
    /// Show a warning alert
    func showWarning(title: String, message: String, onConfirm: (() -> Void)? = nil) {
        self.alertTitle = title
        self.alertMessage = message
        self.alertType = .warning
        self.primaryAction = onConfirm
        self.secondaryAction = nil
        self.primaryButtonText = i18n.t("ok")
        self.secondaryButtonText = ""
        self.isAlertPresented = true
    }
    
    /// Show an error alert
    func showError(title: String, message: String) {
        self.alertTitle = title
        self.alertMessage = message
        self.alertType = .error
        self.primaryAction = nil
        self.secondaryAction = nil
        self.primaryButtonText = i18n.t("ok")
        self.secondaryButtonText = ""
        self.isAlertPresented = true
    }
    
    /// Show a confirmation alert with two buttons
    func showConfirmation(
        title: String,
        message: String,
        confirmText: String,
        cancelText: String,
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.alertTitle = title
        self.alertMessage = message
        self.alertType = .confirmation
        self.primaryAction = onConfirm
        self.secondaryAction = onCancel
        self.primaryButtonText = confirmText
        self.secondaryButtonText = cancelText
        self.isAlertPresented = true
    }
    
    /// Show heavy profile warning
    func showHeavyProfileWarning(onConfirm: @escaping () -> Void) {
        showConfirmation(
            title: i18n.t("heavy.profile.warning.title"),
            message: i18n.t("heavy.profile.warning.message"),
            confirmText: i18n.t("heavy.profile.warning.continue"),
            cancelText: i18n.t("heavy.profile.warning.cancel"),
            onConfirm: onConfirm
        )
    }
    
    /// Show temperature warning
    func showTemperatureWarning(temperature: Double) {
        showWarning(
            title: i18n.t("temperature.warning.title"),
            message: String(format: i18n.t("temperature.warning.text"), temperature)
        )
    }
    
    /// Show auto-reset notification
    func showAutoResetNotification(onAcknowledge: (() -> Void)? = nil) {
        self.alertTitle = i18n.t("calibration.auto.reset.title")
        self.alertMessage = i18n.t("analysis.auto.reset")
        self.alertType = .info
        self.primaryAction = onAcknowledge
        self.secondaryAction = nil
        self.primaryButtonText = i18n.t("got.it")
        self.secondaryButtonText = ""
        self.isAlertPresented = true
    }
    
    /// Show report generation error
    func showReportError(_ error: Error) {
        showError(
            title: i18n.t("error.report.title"),
            message: i18n.t("error.report.message") + "\n\(error.localizedDescription)"
        )
    }
    
    /// Show save error
    func showSaveError(_ error: Error, operation: String) {
        showError(
            title: i18n.t("error.save.title"),
            message: String(format: i18n.t("error.save.message"), operation, error.localizedDescription)
        )
    }
    
    /// Show load error
    func showLoadError(_ error: Error, operation: String) {
        showError(
            title: i18n.t("error.load.title"),
            message: String(format: i18n.t("error.load.message"), operation, error.localizedDescription)
        )
    }
    
    /// Show update error
    func showUpdateError(_ error: Error) {
        showError(
            title: i18n.t("error.update.title"),
            message: i18n.t("error.update.message") + "\n\(error.localizedDescription)"
        )
    }
    
    /// Show GPU error
    func showGPUError(_ error: Error) {
        showError(
            title: i18n.t("error.gpu.title"),
            message: i18n.t("error.gpu.message") + "\n\(error.localizedDescription)"
        )
    }
}

/// ViewModifier to handle AlertManager alerts
struct AlertManagerModifier: ViewModifier {
    @ObservedObject var alertManager = AlertManager.shared
    
    func body(content: Content) -> some View {
        content
            .alert(alertManager.alertTitle, isPresented: $alertManager.isAlertPresented) {
                if alertManager.alertType == .confirmation && !alertManager.secondaryButtonText.isEmpty {
                    Button(alertManager.primaryButtonText, role: alertManager.alertType == .error ? .destructive : .none) {
                        alertManager.primaryAction?()
                    }
                    Button(alertManager.secondaryButtonText, role: .cancel) {
                        alertManager.secondaryAction?()
                    }
                } else {
                    Button(alertManager.primaryButtonText, role: alertManager.alertType == .error ? .none : .cancel) {
                        alertManager.primaryAction?()
                    }
                }
            } message: {
                Text(alertManager.alertMessage)
            }
    }
}

extension View {
    /// Add alert manager support to any view
    func withAlerts() -> some View {
        self.modifier(AlertManagerModifier())
    }
}