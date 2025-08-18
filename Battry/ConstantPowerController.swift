import Foundation
import Combine

/// Параметры PI-регулятора
struct PIParameters {
    let kp: Double      // пропорциональный коэффициент
    let ki: Double      // интегральный коэффициент
    let maxIntegral: Double = 1.0  // ограничение интегральной составляющей
    
    init(kp: Double = 0.10, ki: Double = 0.02) {
        self.kp = kp
        self.ki = ki
    }
}

/// Контроллер постоянной мощности с PI-регулятором
/// Реализует рекомендацию профессора для CP-разряда (constant-power discharge)
@MainActor
final class ConstantPowerController: ObservableObject {
    
    /// Состояние контроллера постоянной мощности
    enum ControlState {
        case idle           // не активен
        case stabilizing    // выход на целевую мощность
        case stable         // поддерживает целевую мощность
        case error(String)  // ошибка регулирования
    }
    
    // MARK: - Published Properties
    
    @Published private(set) var state: ControlState = .idle
    @Published private(set) var targetPowerW: Double = 0
    @Published private(set) var currentPowerW: Double = 0
    @Published private(set) var powerError: Double = 0
    @Published private(set) var dutyCycle: Double = 0.5 // 0...1
    @Published private(set) var controlQuality: Double = 100 // 0-100, качество регулирования
    
    // MARK: - Private Properties
    
    private let piParameters: PIParameters
    private var integralTerm: Double = 0.0
    private var lastUpdateTime: Date?
    private var powerReadingCallback: (() -> Double)?
    private var loadControlCallback: ((Double) -> Void)?
    
    private var controlTimer: AnyCancellable?
    private let controlFrequencyHz: Double = 1.0 // PI регулятор работает на 1 Гц
    
    // Статистика для оценки качества
    private var powerHistory: [Double] = []
    private let historyMaxSize = 60 // последние 60 секунд
    private var stabilizationStartTime: Date?
    
    // MARK: - Initialization
    
    init(piParameters: PIParameters? = nil) {
        self.piParameters = piParameters ?? PIParameters(kp: 0.10, ki: 0.02)
    }
    
    // MARK: - Public Methods
    
    /// Устанавливает коллбэки для чтения мощности и управления нагрузкой
    func setCallbacks(
        powerReading: @escaping () -> Double,
        loadControl: @escaping (Double) -> Void
    ) {
        self.powerReadingCallback = powerReading
        self.loadControlCallback = loadControl
    }
    
    /// Запускает контроллер с заданной целевой мощностью
    func start(targetPower: Double) {
        guard targetPower > 0.1 else {
            state = .error("Target power must be at least 0.1W")
            return
        }
        
        guard powerReadingCallback != nil && loadControlCallback != nil else {
            state = .error("Power reading and load control callbacks must be set")
            return
        }
        
        // Инициализация
        self.targetPowerW = targetPower
        self.integralTerm = 0.0
        self.dutyCycle = 0.5
        self.powerHistory.removeAll()
        self.lastUpdateTime = nil
        self.stabilizationStartTime = Date()
        
        state = .stabilizing
        
        // Запуск PI регулятора на 1 Гц
        controlTimer = Timer.publish(every: 1.0 / controlFrequencyHz, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateControl()
            }
        
        print("ConstantPowerController: Started with target \(targetPower)W")
    }
    
    /// Останавливает контроллер
    func stop() {
        controlTimer?.cancel()
        controlTimer = nil
        
        // Выключаем нагрузку
        loadControlCallback?(0.0)
        
        state = .idle
        targetPowerW = 0
        currentPowerW = 0
        powerError = 0
        dutyCycle = 0.5
        integralTerm = 0.0
        powerHistory.removeAll()
        
        print("ConstantPowerController: Stopped")
    }
    
    /// Изменяет целевую мощность во время работы
    func updateTargetPower(_ newTarget: Double) {
        guard newTarget > 0.1 else { return }
        
        let oldTarget = targetPowerW
        targetPowerW = newTarget
        
        // Сбрасываем интегральную составляющую при значительном изменении цели
        if abs(newTarget - oldTarget) > oldTarget * 0.2 {
            integralTerm = 0.0
            stabilizationStartTime = Date()
            state = .stabilizing
        }
        
        print("ConstantPowerController: Target power updated to \(newTarget)W")
    }
    
    // MARK: - Private Methods
    
    private func updateControl() {
        guard let readPower = powerReadingCallback,
              let controlLoad = loadControlCallback,
              targetPowerW > 0 else { return }
        
        // Читаем текущую мощность
        currentPowerW = readPower()
        
        // Вычисляем ошибку регулирования
        powerError = targetPowerW - currentPowerW
        
        // Обновляем историю мощности
        powerHistory.append(currentPowerW)
        if powerHistory.count > historyMaxSize {
            powerHistory.removeFirst(powerHistory.count - historyMaxSize)
        }
        
        // PI регулятор
        let now = Date()
        let dt: Double
        if let lastTime = lastUpdateTime {
            dt = now.timeIntervalSince(lastTime)
        } else {
            dt = 1.0 / controlFrequencyHz
        }
        lastUpdateTime = now
        
        // Интегральная составляющая
        integralTerm += powerError * piParameters.ki * dt
        integralTerm = max(-piParameters.maxIntegral, min(piParameters.maxIntegral, integralTerm))
        
        // Пропорциональная + интегральная составляющие
        let controlOutput = powerError * piParameters.kp + integralTerm
        
        // Обновляем duty cycle
        dutyCycle += controlOutput
        dutyCycle = max(0.0, min(1.0, dutyCycle))
        
        // Применяем нагрузку
        controlLoad(dutyCycle)
        
        // Оценка качества регулирования и состояния
        updateControlQuality()
        updateControlState()
    }
    
    private func updateControlQuality() {
        guard powerHistory.count >= 10 else {
            controlQuality = 50
            return
        }
        
        // Вычисляем стандартное отклонение мощности за последние данные
        let avgPower = powerHistory.suffix(min(30, powerHistory.count)).reduce(0, +) / Double(min(30, powerHistory.count))
        let variance = powerHistory.suffix(min(30, powerHistory.count)).reduce(0) { sum, power in
            sum + pow(power - avgPower, 2)
        } / Double(min(30, powerHistory.count))
        let stdDev = sqrt(variance)
        
        // Качество основано на стабильности относительно целевой мощности
        let relativeError = abs(avgPower - targetPowerW) / max(0.1, targetPowerW)
        let stability = stdDev / max(0.1, avgPower)
        
        // Формула качества: чем меньше ошибка и нестабильность, тем лучше
        let errorPenalty = min(50.0, relativeError * 200) // максимум 50 очков штрафа за ошибку
        let stabilityPenalty = min(30.0, stability * 300) // максимум 30 очков за нестабильность
        
        controlQuality = max(0, 100 - errorPenalty - stabilityPenalty)
    }
    
    private func updateControlState() {
        let relativeError = abs(powerError) / max(0.1, targetPowerW)
        
        // Проверяем ошибки
        if dutyCycle <= 0.01 && currentPowerW < targetPowerW * 0.5 {
            state = .error("Cannot generate sufficient load")
            return
        }
        
        if dutyCycle >= 0.99 && currentPowerW > targetPowerW * 1.5 {
            state = .error("Cannot reduce load sufficiently")
            return
        }
        
        // Определяем состояние на основе точности
        switch state {
        case .stabilizing:
            // Переходим в stable если ошибка <10% и прошло минимум 30 секунд
            if relativeError < 0.1,
               let startTime = stabilizationStartTime,
               Date().timeIntervalSince(startTime) > 30 {
                state = .stable
            }
            
        case .stable:
            // Возвращаемся в stabilizing если ошибка >20%
            if relativeError > 0.2 {
                state = .stabilizing
                stabilizationStartTime = Date()
            }
            
        case .idle, .error:
            break
        }
    }
}

/// Расширение для удобных методов
extension ConstantPowerController {
    
    /// Возвращает true если контроллер активен
    var isActive: Bool {
        switch state {
        case .idle, .error:
            return false
        case .stabilizing, .stable:
            return true
        }
    }
    
    /// Возвращает true если контроллер стабилизировался на целевой мощности
    var isStable: Bool {
        if case .stable = state {
            return true
        }
        return false
    }
    
    /// Текущая ошибка регулирования в процентах
    var errorPercent: Double {
        guard targetPowerW > 0 else { return 0 }
        return (powerError / targetPowerW) * 100.0
    }
    
    /// Описание состояния для UI
    var stateDescription: String {
        switch state {
        case .idle:
            return "Inactive"
        case .stabilizing:
            return "Stabilizing..."
        case .stable:
            return "Stable"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    /// Получает рекомендуемую интенсивность для LoadGenerator
    func getRecommendedLoadIntensity() -> LoadIntensityRecommendation? {
        guard isActive, targetPowerW > 0 else { return nil }
        
        // Анализируем текущую ошибку и duty cycle для рекомендации
        let powerGap = targetPowerW - currentPowerW
        let _ = powerGap / targetPowerW // relativeGap - может быть использован в будущем
        
        // Определяем рекомендуемый профиль и интенсивность
        let (profile, intensity) = calculateOptimalProfileAndIntensity(
            dutyCycle: dutyCycle,
            powerGap: powerGap,
            targetPower: targetPowerW
        )
        
        return LoadIntensityRecommendation(
            profile: profile,
            intensity: intensity,
            dutyCycle: dutyCycle,
            powerGap: powerGap,
            confidence: min(100, controlQuality)
        )
    }
    
    /// Вычисляет оптимальный профиль и интенсивность
    private func calculateOptimalProfileAndIntensity(
        dutyCycle: Double,
        powerGap: Double,
        targetPower: Double
    ) -> (LoadProfile, Double) {
        
        // Маппинг мощности на профили (типичные значения для MacBook)
        let lightPowerRange = 2.0...8.0    // Вт
        let mediumPowerRange = 6.0...15.0  // Вт
        let heavyPowerRange = 12.0...25.0  // Вт
        
        var recommendedProfile: LoadProfile
        var baseIntensity: Double
        
        // Выбираем профиль на основе целевой мощности
        if lightPowerRange.contains(targetPower) {
            recommendedProfile = .light
            baseIntensity = (targetPower - lightPowerRange.lowerBound) / 
                          (lightPowerRange.upperBound - lightPowerRange.lowerBound)
        } else if mediumPowerRange.contains(targetPower) {
            recommendedProfile = .medium
            baseIntensity = (targetPower - mediumPowerRange.lowerBound) / 
                          (mediumPowerRange.upperBound - mediumPowerRange.lowerBound)
        } else if heavyPowerRange.contains(targetPower) {
            recommendedProfile = .heavy
            baseIntensity = (targetPower - heavyPowerRange.lowerBound) / 
                          (heavyPowerRange.upperBound - heavyPowerRange.lowerBound)
        } else if targetPower < lightPowerRange.lowerBound {
            recommendedProfile = .light
            baseIntensity = 0.2 // минимальная интенсивность
        } else {
            recommendedProfile = .heavy
            baseIntensity = 1.0 // максимальная интенсивность
        }
        
        // Корректируем интенсивность на основе duty cycle и ошибки
        let correctedIntensity = min(1.0, max(0.1, baseIntensity * dutyCycle))
        
        return (recommendedProfile, correctedIntensity)
    }
}

/// Рекомендация по нагрузке для LoadGenerator
struct LoadIntensityRecommendation {
    let profile: LoadProfile
    let intensity: Double      // 0.0 - 1.0
    let dutyCycle: Double     // текущий duty cycle PI-регулятора
    let powerGap: Double      // разница между целевой и текущей мощностью
    let confidence: Double    // уверенность в рекомендации (0-100)
    
    /// Должен ли LoadGenerator изменить настройки
    var shouldUpdate: Bool {
        return abs(powerGap) > 0.5 && confidence > 50
    }
    
    /// Описание рекомендации для отладки
    var description: String {
        return "Profile: \(profile), Intensity: \(String(format: "%.2f", intensity)), DutyCycle: \(String(format: "%.2f", dutyCycle)), Gap: \(String(format: "%.1f", powerGap))W"
    }
}
