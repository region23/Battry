import Foundation
import Combine
import Metal

enum GPUError: Error, LocalizedError {
    case initializationFailed
    
    var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "Failed to initialize GPU compute pipeline"
        }
    }
}

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
    private var gpuEnabled: Bool = false
    private let alertManager = AlertManager.shared
    private var gpuTimer: DispatchSourceTimer?
    private var gpuEngine: GPUComputeEngine?
    // Последние применённые параметры для возможности динамического изменения duty
    private var lastParams: LoadParameters? = nil
    
    /// Запускает генератор с указанным профилем
    func start(profile: LoadProfile) {
        guard !isRunning else { return }
        
        let params = profile.parameters.validated
        currentProfile = profile
        isRunning = true
        lastStopReason = nil
        lastParams = params
        
        // Блокируем сон системы во время работы генератора
        sleepActivity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled],
            reason: "Battry Load Generator Active"
        )
        
        // Создаём рабочие потоки
        startWorkThreads(params: params)
        // Запускаем GPU ветку при необходимости
        if gpuEnabled {
            startGPULoad(params: params)
        }
        
        print("LoadGenerator: Started with profile \(profile) - \(params.threads) threads, \(Int(params.dutyCycle * 100))% duty cycle")
    }
    
    /// Останавливает генератор
    func stop(reason: LoadStopReason = .userStopped) {
        guard isRunning else { return }
        
        stopWorkThreads()
        stopGPULoad()
        
        // Разблокируем сон системы
        if let activity = sleepActivity {
            ProcessInfo.processInfo.endActivity(activity)
            sleepActivity = nil
        }
        
        isRunning = false
        currentProfile = nil
        lastStopReason = reason
        lastParams = nil
        
        print("LoadGenerator: Stopped - \(reason)")
    }

    /// Обновляет интенсивность (duty cycle) без изменения числа потоков и периода
    /// Если генератор не запущен, метод ничего не делает
    func setIntensity(_ intensity: Double) {
        guard isRunning, var params = lastParams else { return }
        // Валидация duty в диапазоне (0.1 ... 0.9)
        let newDuty = max(0.1, min(intensity, 0.9))
        // Перезапускаем рабочие потоки с новыми параметрами
        params = LoadParameters(threads: params.threads, dutyCycle: newDuty, periodMs: params.periodMs).validated
        restartWorkThreads(with: params)
        lastParams = params
    }

    /// Обеспечивает запуск с нужным профилем (перезапускает при смене профиля)
    func ensureProfile(_ profile: LoadProfile) {
        if !isRunning {
            start(profile: profile)
            return
        }
        if let current = currentProfile, current.localizationKey == profile.localizationKey {
            return
        }
        // Профиль изменился — перезапускаем
        stop(reason: .userStopped)
        start(profile: profile)
    }
    
    /// Создаёт и запускает рабочие потоки
    private func startWorkThreads(params: LoadParameters) {
        let workDurationNs = UInt64(Double(params.periodMs) * params.dutyCycle * 1_000_000) // ms -> ns
        let sleepDurationNs = UInt64(Double(params.periodMs) * (1.0 - params.dutyCycle) * 1_000_000)
        
        for _ in 0..<params.threads {
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

    /// Перезапускает рабочие потоки с новыми параметрами
    private func restartWorkThreads(with params: LoadParameters) {
        stopWorkThreads()
        startWorkThreads(params: params)
    }
    
    // MARK: - GPU Load (optional)
    /// Включает/выключает использование GPU для дополнительной нагрузки
    func enableGPU(_ enabled: Bool) {
        gpuEnabled = enabled
        if isRunning {
            if enabled, let profile = currentProfile {
                startGPULoad(params: profile.parameters.validated)
            } else {
                stopGPULoad()
            }
        }
    }

    private func startGPULoad(params: LoadParameters) {
        guard gpuTimer == nil else { return }
        if gpuEngine == nil { 
            gpuEngine = GPUComputeEngine()
            if gpuEngine == nil {
                alertManager.showGPUError(GPUError.initializationFailed)
                return
            }
        }
        guard let engine = gpuEngine else { return }
        let periodMs = params.periodMs
        let duty = params.dutyCycle
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: .milliseconds(periodMs))
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isRunning else { return }
            // Пробуем приблизить длительность работы duty*period
            let workMs = max(1, Int(Double(periodMs) * duty))
            engine.runWork(milliseconds: workMs)
        }
        timer.resume()
        gpuTimer = timer
    }

    private func stopGPULoad() {
        gpuTimer?.cancel()
        gpuTimer = nil
        gpuEngine = nil
    }
    
    deinit {
        // Can't access MainActor isolated properties in deinit
        // Timer cleanup will happen automatically when timers are deallocated
    }
}

// MARK: - Metal GPU Compute Engine
final class GPUComputeEngine {
    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private var pipeline: MTLComputePipelineState?
    private var buffer: MTLBuffer?
    
    init?() {
        self.device = MTLCreateSystemDefaultDevice()
        guard let device = device,
              let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        do {
            let library = try device.makeLibrary(source: GPUComputeEngine.kernelSource, options: nil)
            guard let fn = library.makeFunction(name: "battry_kernel") else { return nil }
            self.pipeline = try device.makeComputePipelineState(function: fn)
            // Prepare a working buffer
            let count = 1 << 20 // ~1M floats (~4MB)
            self.buffer = device.makeBuffer(length: count * MemoryLayout<Float>.size, options: .storageModeShared)
        } catch {
            // Error will be handled by LoadGenerator when gpuEngine is nil
            return nil
        }
    }
    
    func runWork(milliseconds: Int) {
        guard milliseconds > 0, let device = device, let queue = queue, let pipeline = pipeline, let buffer = buffer else { return }
        let start = Date()
        let target = start.addingTimeInterval(Double(milliseconds) / 1000.0)
        // Determine grid sizes
        let gridSize = MTLSize(width: 1 << 20, height: 1, depth: 1)
        let threadGroupSize = MTLSize(width: min(pipeline.maxTotalThreadsPerThreadgroup, 256), height: 1, depth: 1)
        while Date() < target {
            guard let cmd = queue.makeCommandBuffer(), let enc = cmd.makeComputeCommandEncoder() else { break }
            enc.setComputePipelineState(pipeline)
            enc.setBuffer(buffer, offset: 0, index: 0)
            enc.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
            enc.endEncoding()
            cmd.commit()
            // avoid piling up too many CBs
            cmd.waitUntilCompleted()
        }
        _ = device // keep refs
    }
    
    private static let kernelSource: String = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void battry_kernel(device float *outBuffer [[ buffer(0) ]],
                              uint gid [[thread_position_in_grid]]) {
        float acc = float(gid) * 1e-6f;
        // Simple chaotic math to keep ALUs busy
        for (uint i = 0; i < 512; ++i) {
            acc = sin(acc) + cos(acc) + sqrt(fabs(acc) + 1.0f);
        }
        if (gid < 1024) {
            outBuffer[gid] = acc;
        }
    }
    """
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