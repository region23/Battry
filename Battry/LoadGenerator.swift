import Foundation
import Combine

/// Профили нагрузки для генератора CPU
enum LoadProfile {
    case light
    case medium 
    case heavy
    case custom(threads: Int, dutyCycle: Double, periodMs: Int)
    
    /// Конвертирует профиль в параметры нагрузки
    var parameters: LoadParameters {
        switch self {
        case .light:
            return LoadParameters(threads: 1, dutyCycle: 0.25, periodMs: 100)
        case .medium:
            return LoadParameters(threads: 2, dutyCycle: 0.50, periodMs: 100)
        case .heavy:
            return LoadParameters(threads: max(1, ProcessInfo.processInfo.activeProcessorCount), dutyCycle: 0.80, periodMs: 50)
        case .custom(let threads, let dutyCycle, let periodMs):
            return LoadParameters(threads: threads, dutyCycle: dutyCycle, periodMs: periodMs)
        }
    }
    
    /// Локализационный ключ для отображения
    var localizationKey: String {
        switch self {
        case .light: return "load.profile.light"
        case .medium: return "load.profile.medium"
        case .heavy: return "load.profile.heavy"
        case .custom: return "load.profile.custom"
        }
    }
}

/// Параметры нагрузки
struct LoadParameters {
    let threads: Int
    let dutyCycle: Double // 0.0 - 1.0
    let periodMs: Int
    
    /// Безопасная валидация параметров
    var validated: LoadParameters {
        let safeThreads = max(1, min(threads, ProcessInfo.processInfo.activeProcessorCount * 2))
        let safeDuty = max(0.1, min(dutyCycle, 0.9)) // Максимум 90% для безопасности
        let safePeriod = max(50, min(periodMs, 1000))
        return LoadParameters(threads: safeThreads, dutyCycle: safeDuty, periodMs: safePeriod)
    }
}

/// Причины авто-стопа генератора
enum LoadStopReason {
    case userStopped
    case lowBattery(percentage: Int)
    case highTemperature(temperature: Double)
    case thermalPressure(state: ProcessInfo.ThermalState)
    case powerConnected
    case charging
    
    var localizationKey: String {
        switch self {
        case .userStopped: return "load.stop.user"
        case .lowBattery: return "load.stop.battery"
        case .highTemperature: return "load.stop.temperature"
        case .thermalPressure: return "load.stop.thermal"
        case .powerConnected: return "load.stop.power"
        case .charging: return "load.stop.charging"
        }
    }
}

/// Генератор CPU нагрузки с безопасными ограничениями
@MainActor
final class LoadGenerator: ObservableObject {
    /// Текущее состояние генератора
    @Published private(set) var isRunning: Bool = false
    /// Текущий профиль нагрузки
    @Published private(set) var currentProfile: LoadProfile? = nil
    /// Причина последнего останова
    @Published private(set) var lastStopReason: LoadStopReason? = nil
    
    private var workTimers: [DispatchSourceTimer] = []
    private var sleepActivity: NSObjectProtocol?
    
    /// Запускает генератор с указанным профилем
    func start(profile: LoadProfile) {
        guard !isRunning else { return }
        
        let params = profile.parameters.validated
        currentProfile = profile
        isRunning = true
        lastStopReason = nil
        
        // Блокируем сон системы во время работы генератора
        sleepActivity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled],
            reason: "Battry Load Generator Active"
        )
        
        // Создаём рабочие потоки
        startWorkThreads(params: params)
        
        print("LoadGenerator: Started with profile \(profile) - \(params.threads) threads, \(Int(params.dutyCycle * 100))% duty cycle")
    }
    
    /// Останавливает генератор
    func stop(reason: LoadStopReason = .userStopped) {
        guard isRunning else { return }
        
        stopWorkThreads()
        
        // Разблокируем сон системы
        if let activity = sleepActivity {
            ProcessInfo.processInfo.endActivity(activity)
            sleepActivity = nil
        }
        
        isRunning = false
        currentProfile = nil
        lastStopReason = reason
        
        print("LoadGenerator: Stopped - \(reason)")
    }
    
    /// Создаёт и запускает рабочие потоки
    private func startWorkThreads(params: LoadParameters) {
        let workDurationNs = UInt64(Double(params.periodMs) * params.dutyCycle * 1_000_000) // ms -> ns
        let sleepDurationNs = UInt64(Double(params.periodMs) * (1.0 - params.dutyCycle) * 1_000_000)
        
        for threadIndex in 0..<params.threads {
            let timer = DispatchSource.makeTimerSource(
                flags: [],
                queue: DispatchQueue.global(qos: .utility)
            )
            
            timer.schedule(
                deadline: .now(),
                repeating: .milliseconds(params.periodMs)
            )
            
            timer.setEventHandler { [weak self] in
                guard let self = self, self.isRunning else { return }
                
                // Работаем заданное время
                let startTime = DispatchTime.now()
                let endTime = startTime + .nanoseconds(Int(workDurationNs))
                
                // Спин-цикл для создания CPU нагрузки
                var counter: UInt64 = 0
                while DispatchTime.now() < endTime && self.isRunning {
                    counter = counter &+ 1 // Избегаем overflow
                }
                
                // Пауза для соблюдения duty cycle
                if sleepDurationNs > 0 && self.isRunning {
                    Thread.sleep(forTimeInterval: Double(sleepDurationNs) / 1_000_000_000.0)
                }
            }
            
            timer.resume()
            workTimers.append(timer)
        }
    }
    
    /// Останавливает все рабочие потоки
    private func stopWorkThreads() {
        for timer in workTimers {
            timer.cancel()
        }
        workTimers.removeAll()
    }
    
    deinit {
        if isRunning {
            stop()
        }
    }
}

/// Фабрика для создания профиля из процента CPU
extension LoadProfile {
    /// Создаёт профиль на основе желаемого процента CPU
    static func fromPercentage(_ percentage: Int) -> LoadProfile {
        switch percentage {
        case 0..<30:
            return .light
        case 30..<70:
            return .medium
        case 70...100:
            return .heavy
        default:
            return .medium
        }
    }
}