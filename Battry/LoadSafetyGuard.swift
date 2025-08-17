import Foundation
import Combine

/// Настройки безопасности для генератора нагрузки
struct LoadSafetySettings {
    /// Минимальный уровень заряда для работы генератора (%)
    var minBatteryLevel: Int = 7
    /// Максимальная температура батареи (°C)
    var maxTemperature: Double = 35.0
    /// Автостоп при подключении питания
    var stopOnPowerConnected: Bool = true
    /// Автостоп при начале зарядки
    var stopOnCharging: Bool = true
    /// Автостоп при термальном давлении
    var stopOnThermalPressure: Bool = true
}

/// Охранник безопасности для генератора нагрузки
@MainActor
final class LoadSafetyGuard: ObservableObject {
    /// Настройки безопасности
    @Published var settings = LoadSafetySettings()
    /// Флаг активности мониторинга
    @Published private(set) var isMonitoring: Bool = false
    /// Последнее нарушение условий безопасности
    @Published private(set) var lastViolation: SafetyViolation? = nil
    
    private var cancellables = Set<AnyCancellable>()
    private var stopCallback: (LoadStopReason) -> Void
    private var thermalStateObserver: NSObjectProtocol?
    
    /// Инициализирует охранника с колбэком для остановки генератора
    init(stopCallback: @escaping (LoadStopReason) -> Void) {
        self.stopCallback = stopCallback
    }
    
    /// Устанавливает новый callback для остановки генератора
    func setStopCallback(_ callback: @escaping (LoadStopReason) -> Void) {
        self.stopCallback = callback
    }
    
    /// Запускает мониторинг безопасности
    func startMonitoring(batteryPublisher: PassthroughSubject<BatterySnapshot, Never>) {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        lastViolation = nil
        
        // Подписываемся на изменения состояния батареи
        batteryPublisher
            .sink { [weak self] snapshot in
                self?.checkBatterySafety(snapshot)
            }
            .store(in: &cancellables)
        
        // Мониторинг термального состояния системы
        startThermalMonitoring()
        
        print("LoadSafetyGuard: Started monitoring")
    }
    
    /// Останавливает мониторинг
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        cancellables.removeAll()
        stopThermalMonitoring()
        isMonitoring = false
        
        print("LoadSafetyGuard: Stopped monitoring")
    }
    
    /// Проверяет условия безопасности батареи
    private func checkBatterySafety(_ snapshot: BatterySnapshot) {
        // Проверка уровня заряда
        if snapshot.percentage <= settings.minBatteryLevel {
            let violation = SafetyViolation.lowBattery(snapshot.percentage)
            triggerStop(reason: .lowBattery(percentage: snapshot.percentage), violation: violation)
            return
        }
        
        // Проверка температуры
        if snapshot.temperature > settings.maxTemperature {
            let violation = SafetyViolation.highTemperature(snapshot.temperature)
            triggerStop(reason: .highTemperature(temperature: snapshot.temperature), violation: violation)
            return
        }
        
        // Проверка подключения питания
        if settings.stopOnPowerConnected && snapshot.powerSource == .ac {
            let violation = SafetyViolation.powerConnected
            triggerStop(reason: .powerConnected, violation: violation)
            return
        }
        
        // Проверка зарядки
        if settings.stopOnCharging && snapshot.isCharging {
            let violation = SafetyViolation.charging
            triggerStop(reason: .charging, violation: violation)
            return
        }
    }
    
    /// Запускает мониторинг термального состояния
    private func startThermalMonitoring() {
        guard settings.stopOnThermalPressure else { return }
        
        thermalStateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkThermalState()
            }
        }
        
        // Проверяем текущее состояние
        checkThermalState()
    }
    
    /// Останавливает мониторинг термального состояния
    private func stopThermalMonitoring() {
        if let observer = thermalStateObserver {
            NotificationCenter.default.removeObserver(observer)
            thermalStateObserver = nil
        }
    }
    
    /// Проверяет термальное состояние системы
    private func checkThermalState() {
        let thermalState = ProcessInfo.processInfo.thermalState
        
        if thermalState == .serious || thermalState == .critical {
            let violation = SafetyViolation.thermalPressure(thermalState)
            triggerStop(reason: .thermalPressure(state: thermalState), violation: violation)
        }
    }
    
    /// Вызывает остановку генератора
    private func triggerStop(reason: LoadStopReason, violation: SafetyViolation) {
        lastViolation = violation
        stopCallback(reason)
        
        print("LoadSafetyGuard: Safety violation detected - \(violation)")
    }
    
    deinit {
        // Can't call MainActor isolated methods in deinit
        // Combine cancellables and observers will be cleaned up automatically
        cancellables.removeAll()
        if let observer = thermalStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

/// Нарушения условий безопасности
enum SafetyViolation {
    case lowBattery(Int)
    case highTemperature(Double)
    case thermalPressure(ProcessInfo.ThermalState)
    case powerConnected
    case charging
    
    /// Описание нарушения для пользователя
    var localizedDescription: String {
        let i18n = Localization.shared
        switch self {
        case .lowBattery(let percentage):
            return String(format: i18n.t("safety.violation.battery"), percentage)
        case .highTemperature(let temp):
            return String(format: i18n.t("safety.violation.temperature"), temp)
        case .thermalPressure(let state):
            let stateText = state == .critical ? i18n.t("thermal.critical") : i18n.t("thermal.serious")
            return String(format: i18n.t("safety.violation.thermal"), stateText)
        case .powerConnected:
            return i18n.t("safety.violation.power")
        case .charging:
            return i18n.t("safety.violation.charging")
        }
    }
    
    /// Иконка для отображения
    var icon: String {
        switch self {
        case .lowBattery: return "battery.0"
        case .highTemperature: return "thermometer"
        case .thermalPressure: return "exclamationmark.triangle"
        case .powerConnected: return "powerplug"
        case .charging: return "bolt"
        }
    }
    
    /// Цвет для отображения
    var color: String {
        switch self {
        case .lowBattery, .highTemperature, .thermalPressure: return "red"
        case .powerConnected, .charging: return "orange"
        }
    }
}